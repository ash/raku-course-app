# The Raku++ engine as a prebuilt dynamic framework. Rebuild it with
# engine/build-ios.sh in the app repository; nothing is compiled here.
Pod::Spec.new do |s|
  s.name                = 'raku_engine'
  s.version             = '0.1.0'
  s.summary             = 'The Raku++ interpreter for the Learn Raku app.'
  s.homepage            = 'https://raku.online'
  s.license             = { :type => 'Artistic-2.0' }
  s.author              = 'Andrew Shitov'
  s.source              = { :path => '.' }
  s.source_files        = 'Classes/**/*'
  s.vendored_frameworks = 'RakuEngine.xcframework'
  s.platform            = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
