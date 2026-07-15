Pod::Spec.new do |s|
  s.name             = 'olympus_video_sticker'
  s.version          = '1.0.0'
  s.summary          = 'Exportador nativo de figurinhas de video para iOS.'
  s.description      = 'Recorta e converte videos para MP4 sem audio no iOS.'
  s.homepage         = 'https://olympus.local'
  s.license          = { :type => 'Proprietary', :text => 'Copyright Olympus' }
  s.author           = { 'Olympus' => 'app@olympus.local' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.frameworks       = 'AVFoundation'
  s.platform         = :ios, '12.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
