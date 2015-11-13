Pod::Spec.new do |s|
  s.name         = "jetfire"
  s.version      = "0.1.5"
  s.summary      = "WebSocket (RFC 6455) client library for iOS & OS X."
  s.homepage     = "https://github.com/acmacalister/jetfire"
  s.license      = 'Apache License, Version 2.0'
  s.author       = { "Dalton Cherry" => "daltoniam@gmail.com" }
  s.social_media_url = 'http://twitter.com/daltoniam'
  s.source       = { :git => "https://github.com/acmacalister/jetfire.git", :tag => "#{s.version}" }
  s.ios.deployment_target = '6.0'
  s.osx.deployment_target = '10.8'
  s.source_files = '*.{h,m}'
  s.requires_arc = true
end
