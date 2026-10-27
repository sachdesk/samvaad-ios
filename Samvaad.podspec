Pod::Spec.new do |s|
  s.name             = 'Samvaad'
  s.version          = '0.1.0'
  s.summary          = 'Samvaad chat for iOS apps.'
  s.description      = 'Opens your Samvaad chat full screen, keeps the customer signed in, shows an unread count and opens the chat from push notifications.'
  s.homepage         = 'https://github.com/sachdesk/samvaad-ios'
  s.license          = { :type => 'Proprietary', :file => 'LICENSE' }
  s.author           = 'Sachdesk'
  s.source           = { :git => 'https://github.com/sachdesk/samvaad-ios.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.swift_version    = '5.9'

  s.source_files     = 'Sources/Samvaad/**/*.swift'
  s.frameworks       = 'UIKit', 'WebKit', 'SafariServices'
end
