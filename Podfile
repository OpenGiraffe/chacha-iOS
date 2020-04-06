source 'https://cdn.cocoapods.org/'
source 'https://gitlab.linphone.org/BC/public/podspec.git'

project 'chacha-iOS.xcodeproj'
platform:ios,'9.0'

# ignore all warnings from all pods
inhibit_all_warnings!

$PODFILE_PATH = 'liblinphone'

target 'chacha-iOS' do
    use_frameworks!
    
    pod 'libPhoneNumber-iOS'
    pod 'CocoaLumberjack', '3.5.3'
    if File.exist?($PODFILE_PATH)
      pod 'linphone-sdk', :path => $PODFILE_PATH
      else
      pod 'linphone-sdk', '4.3.1'
    end
end

post_install do |installer|
    installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
            config.build_settings['CLANG_MODULES_AUTOLINK'] = 'NO'
        end
    end
end
