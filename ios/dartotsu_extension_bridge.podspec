#
# iOS support for dartotsu_extension_bridge.
#
# The desktop "*_desktop" backends run their fat JARs on a JVM. iOS cannot
# spawn a `java` process and forbids JIT, so this pod embeds an
# interpreter-only OpenJDK Zero runtime in-process and drives the backend JARs
# through it. The approach (static OpenJDK framework loaded lazily via dlopen,
# a dedicated JVM-sized bootstrap thread, Serial GC) is taken from
# https://github.com/kodjodevf/m_extension_server.
#
# TorrServer (torrent streaming engine) is GPL-3.0 and can't spawn a
# subprocess on iOS either, so it's embedded the same way
# github.com/ayman708-UX/torrserver_flutter does it on iOS: a prebuilt
# `gomobile bind` xcframework, statically linked into the app binary. Note
# this makes the whole iOS app binary a GPL-3.0 combined work per FSF
# guidance (desktop/Android instead subprocess the binary, which stays "mere
# aggregation" - no such obligation there).
#
Pod::Spec.new do |s|
  s.name             = 'dartotsu_extension_bridge'
  s.version          = '0.0.1'
  s.summary          = 'Embedded OpenJDK Zero runtime for the dartotsu extension backends on iOS.'
  s.description      = <<-DESC
Runs the Aniyomi / CloudStream / iReader / Tsundoku desktop backend JARs
in-process on iOS using a lazily loaded, interpreter-only OpenJDK framework.
Android and desktop are unaffected (Dalvik bridge / `java` subprocess).
                       DESC
  s.homepage         = 'https://github.com/aayush2622/DartotsuExtensionBridge'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'aayush262' => 'aayush262@users.noreply.github.com' }
  s.source           = { :path => '.' }

  s.source_files = 'dartotsu_extension_bridge/Sources/dartotsu_extension_bridge/**/*.{h,m,mm,swift}'
  s.public_header_files = 'dartotsu_extension_bridge/Sources/dartotsu_extension_bridge/include/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Builds dartotsu_extension_bridge/Frameworks/OpenJDKRuntime.xcframework and
  # stages dartotsu_extension_bridge/Sources/dartotsu_extension_bridge/Runtime/
  # (the embedded-bridge JAR, the java.util.logging shim, cacerts). Idempotent.
  # Also vendors Frameworks/TorrServerKit.xcframework (no build step, just a
  # checksum-verified download+unzip - see PrepareTorrServerRuntime.sh).
  # dartotsu_extension_bridge/Package.swift reads these same generated paths.
  s.prepare_command = 'sh PrepareEmbeddedRuntime.sh && sh PrepareTorrServerRuntime.sh'
  s.vendored_frameworks = [
    'dartotsu_extension_bridge/Frameworks/OpenJDKRuntime.xcframework',
    'dartotsu_extension_bridge/Frameworks/TorrServerKit.xcframework',
  ]
  s.resource_bundles = {
    'dartotsu_extension_bridge_runtime' => ['dartotsu_extension_bridge/Sources/dartotsu_extension_bridge/Runtime/**/*'],
    'dartotsu_extension_bridge_privacy' => ['dartotsu_extension_bridge/Sources/dartotsu_extension_bridge/PrivacyInfo.xcprivacy'],
  }
  s.preserve_paths = 'RuntimeSources/**/*', 'PrepareEmbeddedRuntime.sh', 'PrepareTorrServerRuntime.sh'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'gnu++20',
    'HEADER_SEARCH_PATHS[sdk=iphoneos*]' =>
      '$(inherited) "$(PODS_TARGET_SRCROOT)/dartotsu_extension_bridge/Frameworks/OpenJDKRuntime.xcframework/ios-arm64/OpenJDKRuntime.framework/Headers"',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '5.0'
end
