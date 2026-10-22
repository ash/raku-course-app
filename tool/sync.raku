#!/usr/bin/env raku

# Course of Raku — content sync script.
#
# Reads the raku-course repository (read-only) and emits a single
# assets/data/content.json that the Flutter app bundles and renders offline.
#
# Usage:
#   raku tool/sync.raku [--no-run-check] [/path/to/raku-course] > assets/data/content.json
#
# The course root defaults to ~/raku-course.
#
# Every Raku code block is run once with the Raku++ engine (`rakupp` on PATH,
# or $RAKUPP) to mark the ones the app can offer a Run button for; that pass
# takes about a minute, and --no-run-check skips it.
#
# It mirrors the course's own generator (raku-course/raku-pages.raku):
#   * structure is driven strictly by _data/toc/en.yaml (English only),
#   * URL levels are  /part/section/topic  (subparts are display-only),
#   * exercises live at  <parent>/exercises/<url>/  with a  /solution  page.
#
# The script is the ONLY place markdown is parsed; the app ships pre-digested
# blocks so it needs no markdown/yaml dependency.

use YAMLish;

my @args = @*ARGS;
my $RUN-CHECK = !@args.grep('--no-run-check');
@args .= grep(* ne '--no-run-check');
my $ENGINE = %*ENV<RAKUPP> // 'rakupp';
my $ROOT = (@args[0] // %*ENV<HOME> ~ '/raku-course').IO;
die "Course root not found: $ROOT" unless $ROOT.d;

# ---------------------------------------------------------------------------
# Minimal JSON encoder (JSON::Fast is not installed in this toolchain).
# ---------------------------------------------------------------------------
sub to-json($v) {
    given $v {
        when Nil           { 'null' }
        when Bool          { $v ?? 'true' !! 'false' }
        when Int           { ~$v }
        when Numeric       { ~$v }
        when Str           { json-str($v) }
        when Positional    { '[' ~ $v.map(&to-json).join(',') ~ ']' }
        when Associative   {
            '{' ~ $v.kv.map(-> $k, $val {
                # Titles are shown as plain text in the app, where the
                # course's `code` backticks would appear literally.
                my $out = $k eq 'title' | 'longTitle' && $val ~~ Str ?? $val.subst('`', '', :g) !! $val;
                json-str(~$k) ~ ':' ~ to-json($out)
            }).join(',') ~ '}'
        }
        default            { json-str(~$v) }
    }
}

sub json-str(Str $s) {
    my $out = '"';
    for $s.comb -> $c {
        given $c {
            when '"'  { $out ~= '\"' }
            when '\\' { $out ~= '\\\\' }
            when "\n" { $out ~= '\n' }
            when "\r" { $out ~= '\r' }
            when "\t" { $out ~= '\t' }
            default {
                my $o = $c.ord;
                $out ~= $o < 0x20 ?? sprintf('\u%04x', $o) !! $c;
            }
        }
    }
    return $out ~ '"';
}

# ---------------------------------------------------------------------------
# Text helpers
# ---------------------------------------------------------------------------
sub html-decode(Str $s is copy) {
    $s .= subst('&lt;',   '<',  :g);
    $s .= subst('&gt;',   '>',  :g);
    $s .= subst('&quot;', '"',  :g);
    $s .= subst('&apos;', "'",  :g);
    $s .= subst('&nbsp;', ' ',  :g);
    $s .= subst('&amp;',  '&',  :g);   # must be last
    return $s;
}

# Strip Liquid tags, YAML frontmatter, HTML noise; return the markdown body.
sub clean-markdown(Str $raw is copy) {
    # YAML frontmatter
    $raw .= subst(/ ^ '---' \n .*? \n '---' \n /, '');

    # Protect fenced code blocks so the prose-only substitutions below never
    # touch literal code or terminal output. Without this, a hash dump such as
    #   {:alpha("a"), :beta("b"), :gamma("g")}
    # is mistaken for a Kramdown attribute list ({: … }) and silently deleted,
    # leaving an empty terminal block. Placeholders use a private-use codepoint
    # that cannot appear in the source, and are restored at the end.
    my @fences;
    $raw .= subst(/ '```' .*? \n '```' /, -> $m {
        @fences.push(~$m);
        "\x[E000]{@fences.end}\x[E000]"
    }, :g);

    # Liquid tags  {% ... %}  and  {{ ... }}
    $raw .= subst(/ '{%' .*? '%}' /, '', :g);
    $raw .= subst(/ '{{' .*? '}}' /, '', :g);
    # Kramdown inline attribute lists, e.g. {:.note} — but NOT {:.quiz}
    #   (quiz blocks are handled separately and never reach here).
    $raw .= subst(/ '{:' <-[}]>* '}' /, '', :g);
    # <style>…</style> blocks (only the About page has one)
    $raw .= subst(/ '<style' .*? '</style>' /, '', :g);
    # HTML comments
    $raw .= subst(/ '<!--' .*? '-->' /, '', :g);
    # Trailing manual "Course navigation" section (About page only)
    $raw .= subst(/ \n '## Course navigation' .* $ /, '');

    # Restore the protected code blocks.
    $raw .= subst(/ \x[E000] (\d+) \x[E000] /, -> $m {
        @fences[+$m[0]]
    }, :g);

    return $raw;
}

# ---------------------------------------------------------------------------
# Markdown → blocks
#
# Block shapes:
#   { t => 'p',          v => text }
#   { t => 'h', level=>N, v => text }
#   { t => 'code',  lang => 'raku'|'json'|…, v => code, run => True? }
#   { t => 'codeOutput', v => terminal session }
#   { t => 'output', v => what a program prints (a bare ``` fence) }
#   { t => 'ul', items => [...] } / { t => 'ol', items => [...] }
#   { t => 'tip', v => text }
# ---------------------------------------------------------------------------
sub block-start(Str $l) returns Bool {
    return True if $l ~~ / ^ \s* $ /;
    return True if $l ~~ / ^ \s* '```' /;
    return True if $l ~~ / ^ '#' '#'+ \s /;
    return True if $l ~~ / ^ \s* '>' /;
    return True if $l ~~ / ^ \s* <[-*]> \s /;
    return True if $l ~~ / ^ \s* \d+ '.' \s /;
    return True if $l ~~ / ^ \s* '|' /;
    return False;
}

sub parse-blocks(Str $body) returns Array {
    my @lines = $body.lines;
    my @blocks;
    my $i = 0;

    sub push-para(@buf) {
        return unless @buf;
        my $text = html-decode(@buf.join(' ').trim);
        @blocks.push({ t => 'p', v => $text }) if $text;
    }

    while $i < @lines.elems {
        my $line = @lines[$i];

        # Fenced code block
        if $line ~~ / ^ \s* '```' (\w*) \s* $ / {
            my $lang = ~$0;
            my @code;
            $i++;
            while $i < @lines.elems && @lines[$i] !~~ / ^ \s* '```' \s* $ / {
                @code.push(@lines[$i]);
                $i++;
            }
            $i++;  # closing fence
            my $code = @code.join("\n");
            if $lang eq 'console' || $lang eq 'shell' || $lang eq 'bash' {
                @blocks.push({ t => 'codeOutput', v => html-decode($code) });
            }
            elsif $lang eq '' {
                # A bare fence is what a program prints — the course site renders
                # it plain, never highlighted as Raku.
                @blocks.push({ t => 'output', v => html-decode($code) });
            }
            else {
                @blocks.push({ t => 'code', lang => $lang, v => html-decode($code) });
            }
            next;
        }

        # Heading (## … ######)
        if $line ~~ / ^ ('#' '#'+) \s+ (.*) $ / {
            my $level = min($0.Str.chars, 4);
            @blocks.push({ t => 'h', level => $level, v => html-decode(~$1).trim });
            $i++;
            next;
        }

        # Blockquote → tip
        if $line ~~ / ^ \s* '>' \s? / {
            my @quote;
            while $i < @lines.elems && @lines[$i] ~~ / ^ \s* '>' \s? (.*) $ / {
                @quote.push(~$0);
                $i++;
            }
            my $text = html-decode(@quote.join(' ').trim);
            @blocks.push({ t => 'tip', v => $text }) if $text;
            next;
        }

        # Unordered list
        if $line ~~ / ^ \s* <[-*]> \s+ (.+) $ / {
            my @items;
            while $i < @lines.elems && @lines[$i] ~~ / ^ \s* <[-*]> \s+ (.+) $ / {
                @items.push(html-decode(~$0).trim);
                $i++;
            }
            @blocks.push({ t => 'ul', items => @items });
            next;
        }

        # Ordered list
        if $line ~~ / ^ \s* \d+ '.' \s+ (.+) $ / {
            my @items;
            while $i < @lines.elems && @lines[$i] ~~ / ^ \s* \d+ '.' \s+ (.+) $ / {
                @items.push(html-decode(~$0).trim);
                $i++;
            }
            @blocks.push({ t => 'ol', items => @items });
            next;
        }

        # Markdown table → skip (only the About page has one)
        if $line ~~ / ^ \s* '|' / {
            $i++;
            next;
        }

        # Blank line → paragraph break
        if $line ~~ / ^ \s* $ / {
            $i++;
            next;
        }

        # Paragraph: accumulate consecutive plain lines
        my @buf;
        while $i < @lines.elems && !block-start(@lines[$i]) {
            @buf.push(@lines[$i]);
            $i++;
        }
        push-para(@buf);
    }

    return @blocks;
}

# ---------------------------------------------------------------------------
# Read a page's index.md and return its blocks (empty if missing/blank).
# ---------------------------------------------------------------------------
sub page-blocks(Str $url) returns Array {
    my $path = $ROOT.add("$url/index.md");
    return [] unless $path.e;
    return parse-blocks(clean-markdown($path.slurp));
}

# Plain-text flattening of blocks, for the search index.
sub blocks-text(@blocks) {
    @blocks.map(-> $b {
        ($b<v> // ''), |($b<items> // []).flat
    }).flat.join(' ');
}

# ---------------------------------------------------------------------------
# Quiz parsing
# ---------------------------------------------------------------------------
# The course has three quiz formats:
#   {:.quiz}         standard multiple-choice  → rendered as an interactive card
#   {:.quiz-select}  fill-in / pick-the-option → rendered as a reveal card
#   {:.quiz-code...} code-completion grids     → rendered as a reveal card
# Reveal cards show the question and a "Show answer" with the correct answer(s),
# preserving the content without trying to reproduce the interactive widget.
sub parse-quiz(Str $url, Str $title) {
    my $path = $ROOT.add("$url/index.md");
    return Nil unless $path.e;
    my $raw = $path.slurp;
    $raw .= subst(/ ^ '---' \n .*? \n '---' \n /, '');   # frontmatter
    $raw .= subst(/ '{%' .*? '%}' /, '', :g);            # liquid (keep {: markers)

    # --- Standard multiple-choice ---------------------------------------
    if $raw ~~ / '{:.quiz}' / {
        my ($prompt-part, $answers-part) = $raw.split(/'{:.quiz}'/, 2);
        my @options;
        for $answers-part.lines -> $line {
            next unless $line ~~ / ^ \s* (<[01]>) \s* '|' \s* (.*) $ /;
            my @parts = (~$1).split(/\s* '|' \s*/);
            my $text  = html-decode(@parts[0].trim);
            my $why   = @parts[1].defined ?? html-decode(@parts[1..*].join(' | ').trim) !! Nil;
            @options.push({ text => $text, ok => (~$0 eq '1'), ($why ?? (why => $why) !! Empty) });
        }
        return Nil unless @options;
        return {
            kind    => 'choice',
            title   => $title,
            prompt  => parse-blocks(clean-markdown($prompt-part // '')),
            options => @options,
            multi   => @options.grep(*<ok>).elems > 1,
        };
    }

    # --- Fill-in / code-completion → reveal card ------------------------
    return Nil unless $raw ~~ / '{:.quiz' /;
    my @prompt-lines;
    my @rows;
    my $answer-mode = False;
    for $raw.lines -> $line {
        if $line ~~ / ^ \s* '{:.quiz' / { $answer-mode = True; next; }
        if $line ~~ / ^ \s* $ /        { $answer-mode = False; @prompt-lines.push(''); next; }
        if $answer-mode {
            my @parts = $line.split(/\s* '|' \s*/);
            next unless @parts;
            my $a    = blank-fill(html-decode(@parts[0].trim));
            my $q    = @parts[1].defined ?? blank-fill(html-decode(@parts[1].trim)) !! '';
            my $why  = @parts[2].defined ?? html-decode(@parts[2..*].join(' | ').trim) !! Nil;
            @rows.push({ q => $q, a => $a, ($why ?? (why => $why) !! Empty) });
        }
        else {
            @prompt-lines.push($line);
        }
    }
    return Nil unless @rows;
    return {
        kind   => 'reveal',
        title  => $title,
        prompt => parse-blocks(clean-markdown(@prompt-lines.join("\n"))),
        rows   => @rows,
    };
}

# Make fill-in placeholders visible: ␣ blanks and (: choices :) become a box.
sub blank-fill(Str $s is copy) {
    $s .= subst(/ '(:' .*? ':)' /, '▢', :g);
    $s .= subst('␣', '▢', :g);
    return $s.trim;
}

# ---------------------------------------------------------------------------
# Exercise parsing (prompt + solution page; both are markdown).
# ---------------------------------------------------------------------------
sub parse-exercise(Str $url, Str $title) {
    # Prompt: strip the trailing "## Solution / See the solution" pointer.
    my $prompt-path = $ROOT.add("$url/index.md");
    my @prompt;
    if $prompt-path.e {
        my $raw = clean-markdown($prompt-path.slurp);
        $raw .= subst(/ \n '## Solution' .* $ /, '');   # drop solution pointer
        @prompt = parse-blocks($raw);
    }

    # Solution: separate page; drop the 🦋 "source code" GitHub link line.
    my $sol-path = $ROOT.add("$url/solution/index.md");
    my @solution;
    if $sol-path.e {
        my $raw = clean-markdown($sol-path.slurp);
        $raw = $raw.lines.grep({ $_ !~~ / '🦋' / }).join("\n");
        @solution = parse-blocks($raw);
    }

    return {
        id       => $url,
        title    => $title,
        prompt   => @prompt,
        solution => @solution,
    };
}

# ---------------------------------------------------------------------------
# The Final Test's question bank (assets/final-test-questions.js).
#
# It is a JavaScript literal, not JSON — bare keys, single- or double-quoted
# strings, trailing commas, comments — so it is read with a grammar for exactly
# that subset. Each item: { part, topic, type, q, code?, options?, answer,
# explain }, where type is choice / multi / boolean / input.
# ---------------------------------------------------------------------------
grammar JSLiteral {
    rule  TOP    { <.ws> 'window.' <.ident> '=' <array> ';'? }
    rule  value  { <object> | <array> | <string> | <number> | <bool> }
    rule  array  { '[' [ <value>* %% ',' ] ']' }
    rule  object { '{' [ <pair>* %% ',' ] '}' }
    rule  pair   { <key=.ident> ':' <value> }
    token string { \' $<s>=[ <-['\\]> | \\ . ]* \' | \" $<s>=[ <-["\\]> | \\ . ]* \" }
    token number { '-'? \d+ [ '.' \d+ ]? }
    token bool   { true | false }
    token ws     { [ \s+ | '/*' .*? '*/' | '//' \N* ]* }
}

class JSLiteralValues {
    method TOP($/)    { make $<array>.made }
    method value($/)  { make ($<object> // $<array> // $<string> // $<number> // $<bool>).made }
    method array($/)  { make [ $<value>.map(*.made) ] }
    method object($/) { make %( $<pair>.map({ ~.<key> => .<value>.made }) ) }
    method string($/) {
        make (~$<s>).subst(/ \\ (.) /, {
            given ~$0 {
                when 'n' { "\n" }
                when 't' { "\t" }
                when 'r' { "\r" }
                default  { $_ }
            }
        }, :g)
    }
    method number($/) { make +$/ }
    method bool($/)   { make $/ eq 'true' }
}

sub final-test-questions(Str $url) {
    return () unless $url eq 'final-test';
    my $file = $ROOT.add('assets/final-test-questions.js');
    return () unless $file.e;
    my $m = JSLiteral.parse($file.slurp, actions => JSLiteralValues);
    die "Cannot parse $file" unless $m;
    my @q = $m.made;
    note "Final Test questions: {@q.elems}";
    @q
}

# ---------------------------------------------------------------------------
# TOC walk → flat ordered pages (the spine) + per-part navigation tree.
# ---------------------------------------------------------------------------
my @pages;          # flat, ordered list of lesson pages
my $order = 0;

# Walk one content level (section / topic / sub-topic). Returns a TocNode.
sub walk-level($level, Str $parent-url, Int $part-index) {
    my $url = "$parent-url/$level<url>";

    my @blocks = page-blocks($url);

    # Attached quizzes
    my @quizzes;
    if $level<quizzes> {
        for @($level<quizzes>) -> $q {
            my $quiz = parse-quiz("$url/$q<url>", $q<title>);
            @quizzes.push($quiz) if $quiz;
        }
    }

    # Attached exercises
    my @exercises;
    if $level<exercises> {
        for @($level<exercises>) -> $e {
            @exercises.push(parse-exercise("$url/exercises/$e<url>", $e<title>));
        }
    }

    my %page =
        id        => $url,
        title     => $level<title>,
        ($level<long_title> ?? (longTitle => $level<long_title>) !! Empty),
        part      => $part-index,
        order     => $order++,
        blocks    => @blocks,
        quizzes   => @quizzes,
        exercises => @exercises;

    # Precomputed lowercased search text.
    %page<searchText> = (
        %page<title>,
        blocks-text(@blocks),
        @quizzes.map({
            blocks-text($_<prompt>),
            ($_<options> // []).map(*<text>).join(' '),
            ($_<rows>    // []).map({ $_<q>, $_<a> }).flat.join(' '),
        }).flat,
        @exercises.map({ $_<title>, blocks-text($_<prompt>) }).flat,
    ).flat.join(' ').lc;

    @pages.push(%page);

    # Recurse into topics.
    my @children;
    if $level<items> {
        for @($level<items>) -> $child {
            @children.push(walk-level($child, $url, $part-index));
        }
    }

    return {
        title => $level<title>,
        page  => $url,
        (@quizzes   ?? (quizzes   => @quizzes.elems)   !! Empty),
        (@exercises ?? (exercises => @exercises.elems) !! Empty),
        (@children  ?? (children  => @children)        !! Empty),
    };
}

# ---------------------------------------------------------------------------
# Build the parts.
# ---------------------------------------------------------------------------
my $toc = load-yamls($ROOT.add('_data/toc/en.yaml').slurp)[0];

# The course marks recent additions with 🆕 in its TOC. The app leaves the
# labels out: to someone installing it, all of it is new.
sub drop-new-labels($node) {
    if $node ~~ Associative {
        for <title long_title> -> $k {
            $node{$k} = $node{$k}.subst(/ \s* '🆕' /, '', :g).trim if $node{$k} ~~ Str;
        }
        drop-new-labels($_) for $node.values;
    }
    elsif $node ~~ Positional {
        drop-new-labels($_) for @$node;
    }
}
drop-new-labels($toc);

my @parts;
my $part-index = 0;

for @($toc<toc>) -> $part {
    my @toc-tree;

    if $part<items> {
        # A normal multi-section part: items are subparts (display-only headings).
        for @($part<items>) -> $subpart {
            my @sections;
            for @($subpart<items> // []) -> $section {
                @sections.push(walk-level($section, $part<url>, $part-index));
            }
            @toc-tree.push({
                title    => $subpart<title>,
                children => @sections,
            });
        }
    }
    else {
        # A single-page part (e.g. "About this course").
        my @blocks = page-blocks($part<url>);
        my @final-test = final-test-questions($part<url>);
        # The Final Test's page is a JavaScript widget on the site; keep its
        # prose, drop the markup, and carry the question bank so the app can
        # run the test itself.
        @blocks .= grep({ .<t> ne 'p' || .<v> !~~ / ^ \s* '<' / }) if @final-test;
        my %page =
            id     => $part<url>,
            title  => $part<title>,
            part   => $part-index,
            order  => $order++,
            blocks => @blocks,
            quizzes => [],
            exercises => [],
            (@final-test ?? (finalTest => @final-test) !! Empty),
            searchText => ($part<title>, blocks-text(@blocks)).join(' ').lc;
        @pages.push(%page);
        @toc-tree.push({ title => $part<title>, page => $part<url> });
    }

    @parts.push({
        i           => $part-index,
        title       => $part<title>,
        ($part<long_title>  ?? (longTitle   => $part<long_title>)  !! Empty),
        slug        => $part<url>,
        ($part<description> ?? (description => $part<description>.subst(/\s+/, ' ', :g).trim) !! Empty),
        toc         => @toc-tree,
    });

    $part-index++;
}

# ---------------------------------------------------------------------------
# Which Raku blocks run on their own?
#
# The app carries the Raku++ engine and puts a Run button on a code block —
# but many blocks are fragments that lean on an earlier one (`say $rex.name`)
# or need a file, a server or command-line arguments, and a Run that only
# ever prints "Variable '$rex' is not declared" teaches nothing; nor does one
# for a block that only declares variables and prints nothing. So every block
# is run here, natively, with a time limit, and only the ones that finish
# cleanly AND print something get `run => True`. A block that reads input
# (in the app, the learner types it when asked) is checked with sample input.
# The rest can still be opened in the app's playground.
# ---------------------------------------------------------------------------
sub mark-runnable(@pages) {
    my @code-blocks = gather for @pages -> %page {
        my @lists = %page<blocks>,
                    |%page<quizzes>.map(*<prompt>),
                    |%page<exercises>.map({ |($_<prompt>, $_<solution>) });
        for @lists -> @list {
            take $_ for @list.grep({ $_<t> eq 'code' && $_<lang> eq 'raku' });
        }
    };

    my @queue = @code-blocks.map(*<v>).unique;
    my %ok;
    my $lock = Lock.new;
    my $tmp = $*TMPDIR.add("learn-raku-sync-$*PID");
    await (^4).map: -> $worker {
        start {
            my $dir = $tmp.add("w$worker");
            $dir.mkdir;
            loop {
                my $code = $lock.protect: { @queue ?? @queue.shift !! Nil };
                last without $code;
                my $ok = runs-cleanly($code, $dir);
                $lock.protect: { %ok{$code} = $ok };
            }
        }
    };
    run 'rm', '-rf', ~$tmp;

    my $n = 0;
    for @code-blocks -> $b {
        next unless %ok{$b<v>};
        $b<run> = True;
        $n++;
    }
    note "Runnable Raku blocks: $n of {@code-blocks.elems}";
}

sub runs-cleanly(Str $code, IO::Path $dir) returns Bool {
    # A phone cannot start processes: these would pass here and fail in the app.
    return False if $code ~~ / << [ run | shell | qx | QX ] >> \s* <[(\s'"{]> /;
    return False if $code ~~ / 'Proc::Async' /;

    my $proc = Proc::Async.new($ENGINE, '-e', $code, :w);
    my $printed = 0;
    $proc.stdout.tap(-> $s { $printed += $s.chars });
    $proc.stderr.tap(-> $s { $printed += $s.chars });
    my $done = $proc.start(:cwd($dir));
    # Much the test raku.online's widget uses to decide a block reads stdin.
    await $proc.print("42\n" x 20) if reads-input($code);
    $proc.close-stdin;
    await Promise.anyof($done, Promise.in(5));
    if $done.status ~~ Planned {
        $proc.kill(SIGKILL);
        return False;
    }
    return $done.result.exitcode == 0 && $printed > 0;
}

sub reads-input(Str $code) returns Bool {
    so $code ~~ / '$*IN' >> | [ ^ | <-[.\w$@%&]> ] [ get | prompt | lines ] >> /;
}

mark-runnable(@pages) if $RUN-CHECK;

# ---------------------------------------------------------------------------
# Emit.
# ---------------------------------------------------------------------------
my %course =
    appTitle => 'Learn Raku',
    tagline  => 'Learn the Raku programming language, offline.',
    credit   => 'Andrew Shitov',
    parts    => @parts,
    pages    => @pages;

# Stats to STDERR so STDOUT stays pure JSON.
my $lessons   = @pages.elems;
my $quizzes   = @pages.map({ $_<quizzes>.elems }).sum;
my $exercises = @pages.map({ $_<exercises>.elems }).sum;
note "Parts: {@parts.elems}  Lessons: $lessons  Quizzes: $quizzes  Exercises: $exercises";

say to-json(%course);
