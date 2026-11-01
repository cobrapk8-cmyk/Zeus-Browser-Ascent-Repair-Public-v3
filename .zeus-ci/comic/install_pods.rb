require 'pathname'
project = Pathname.new(ARGV.fetch(0)).expand_path
names = ARGV.drop(1)
raise 'Expected Xcode project and targets' if names.empty?
text = "platform :ios, '18.1'\nuse_frameworks! :linkage => :static\nproject '#{project.basename}'\n"
names.each do |name|
  text << "target '#{name}' do\n"
  %w[TextRecognition TextRecognitionChinese TextRecognitionJapanese TextRecognitionKorean].each do |part|
    text << "  pod 'GoogleMLKit/#{part}', '9.0.0'\n"
  end
  text << "end\n"
end
text << <<~RUBY
  post_install do |installer|
    installer.pods_project.targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '18.1'
      end
    end
  end
RUBY
(project.dirname + 'Podfile').write(text)
