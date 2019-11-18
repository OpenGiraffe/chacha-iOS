source 'https://github.com/CocoaPods/Specs.git'

xcodeproj 'chacha-iOS.xcodeproj'
platform:ios,'8.0'
use_frameworks!
# ignore all warnings from all pods
inhibit_all_warnings!

target 'chacha-iOS' do

post_install do |installer|
    installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
            config.build_settings['CLANG_MODULES_AUTOLINK'] = 'NO'
        end
    end
end


end
