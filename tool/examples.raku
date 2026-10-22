#!/usr/bin/env raku

# Playground examples — the example programs that ship with Raku++.
#
# Reads examples/README.md (for the categories and one-line descriptions) and
# each examples/*.raku from the Raku++ git repository at the same tag the
# app's engine is built from (engine/build-ios.sh), so an example never uses a
# feature the bundled engine lacks. Writes JSON for assets/data/examples.json.
#
# Usage:
#   raku tool/examples.raku [--repo=~/raku++] [--ref=v5.4.1] > assets/data/examples.json

sub MAIN(Str :$repo = "$*HOME/raku++", Str :$ref = 'v5.4.1') {
    # Programs that do not suit a phone screen: a live ANSI animation and a
    # socket server that never returns.
    my %skip = :life, :echo-server;

    sub git-show(Str $path) {
        my $p = run 'git', '-C', $repo, 'show', "$ref:$path", :out, :err;
        my $text = $p.out.slurp(:close);
        $p.err.slurp(:close);
        die "git show $ref:$path failed" unless $p.exitcode == 0;
        $text
    }

    my @examples;
    my $category = '';
    for git-show('examples/README.md').lines -> $line {
        if $line ~~ / ^ '|' \s* '**' (<-[*]>+) '**' / {
            $category = ~$0;
            next;
        }
        next unless $line ~~ / ^ '|' \s* '[`' (<[\w-]>+) '.raku`]' .*? '|' \s* (<-[|]>+?) \s* '|' \s* (<-[|]>+?) \s* '|' /;
        my ($name, $what, $focus) = ~$0, ~$1, ~$2;
        next if %skip{$name};
        my $code = git-show("examples/$name.raku");
        # The `#!` line means nothing in the app — unless the program quotes
        # it, as the quine does to print itself exactly.
        my ($first, $rest) = $code.split("\n", 2);
        $code = $rest if $first.starts-with('#!') && !$rest.contains($first);
        @examples.push: %(
            name     => $name,
            category => $category,
            title    => $what,
            focus    => $focus.subst('`', '', :g),
            code     => $code,
        );
    }

    note "Examples: {@examples.elems} (from $ref)";
    say to-json(@examples);
}

sub to-json($v) {
    given $v {
        when Positional  { '[' ~ $v.map(&to-json).join(",\n") ~ ']' }
        when Associative { '{' ~ $v.sort(*.key).map({ json-str(.key) ~ ':' ~ to-json(.value) }).join(',') ~ '}' }
        default          { json-str(~$v) }
    }
}

sub json-str(Str $s) {
    '"' ~ $s.trans(['\\', '"', "\n", "\t", "\r"] => ['\\\\', '\"', '\n', '\t', '\r']) ~ '"'
}
