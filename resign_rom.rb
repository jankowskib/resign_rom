#!/usr/bin/env ruby
#
#   resign_rom.rb
#   Copyright 2015 Bartosz Jankowski
#
#   Licensed under the Apache License, Version 2.0 (the 'License');
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an 'AS IS' BASIS
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#

require 'optparse'
require 'openssl'

KEY_REF_APKS = {:pk => "Settings", :sk => "ContactsProvider", :rk => "HTMLViewer",
            :mk => "DownloadProvider" }

def get_apk_sha1(apk)
    cmd = "keytool -printcert -jarfile " << apk
    result = `#{cmd}`
    raise "Failed to obtain SHA1 of APK. Make sure you have the newest version" <<
      " of keytool!" if result.empty?
    result[/SHA1: (.*)/, 1]
end

def resign_apk(apk, key)
  tmpfile = File.basename(apk) << ".tmp"
  cmd = "java -jar %s/#{SIGN_APK_BIN} -w -v %s.x509.pem %s.pk8 %s %s"  % [File.dirname($0), key, key, apk, tmpfile ]
  system(cmd)
  cmd2 = "zipalign -vf 4 %s %s" % [tmpfile, apk]
  system(cmd2)
  File.delete tmpfile
end

def resign_apks(key_apk_name, key)
  ref_apk = ($files.keys.grep /#{key_apk_name}/).first
  raise "Didn't find a #{key_apk_name}.apk in ROM directory. " <<
    "Cannot determine an old key!" unless ref_apk
  old_platform_key = $files[ref_apk]
  cert = OpenSSL::X509::Certificate.new File.read(key + ".x509.pem" )
  new_platform_key = OpenSSL::Digest::SHA1.new(cert.to_der).to_s.scan(/../).map{ |s| s.upcase }.join(":")
  puts "Old platform key:" << old_platform_key
  puts "New plaform key: " << new_platform_key
  raise "#{key} is the same as #{key_apk_name}!" if new_platform_key == old_platform_key
  $files.select { |k, v| v == old_platform_key }.keys.each do |f|
      resign_apk(f, key)
  end
end

begin
$options = {}
$files = {}

JAVA_VERSION = `java -version 2>&1`[/"(.*)"/,1]
raise "Java is not installed!" unless JAVA_VERSION
raise "keytool not found!" if `which keytool`.empty?
raise "zipalign not found!" if `which zipalign`.empty?

SIGN_APK_BIN = (JAVA_VERSION[2] == 6 ? "SignApkv2.jar" : "SignApkv2_java7.jar")
  OptionParser.new do |opts|
    opts.banner = "Usage: pack [options]"
    opts.separator "Options:"
    opts.on("-d", "--dir DIR", "Set a ROM directory") { |t| $options[:dir] = t }
    opts.on("-p", "--platform KEY", "Set a plaform key") { |t| $options[:pk] = t[/^(.+?)(?:\.|$)/, 1] }
    opts.on("-s", "--shared KEY", "Set a shared key") { |t| $options[:sk] = t[/^(.+?)(?:\.|$)/, 1] }
    opts.on("-m", "--media KEY", "Set a media key") { |t| $options[:mk] = t[/^(.+?)(?:\.|$)/, 1] }
    opts.on("-r", "--release KEY", "Set a release key") { |t| $options[:rk] = t[/^(.+?)(?:\.|$)/, 1] }
  end.parse!

    raise "Please specify a directory" unless $options[:dir]
    raise "Please specify at least one of key (platform, shared, media, release)" unless
      $options[:pk] || $options[:rk] || $options[:mk] || $options[:sk]

    puts "Resigning in: " << File.join($options[:dir], "**/", "*.apk")
    print "Checking old signatures..."
    Dir.glob(File.join($options[:dir], "**/", "*.apk")) do |f|
      print "\rChecking old signatures..." << File.basename(f) << " "*16
      $files[f] = get_apk_sha1(f)
    end
    puts

    resign_apks(KEY_REF_APKS[:pk], $options[:pk]) if $options[:pk]
    resign_apks(KEY_REF_APKS[:sk], $options[:sk]) if $options[:sk]
    resign_apks(KEY_REF_APKS[:mk], $options[:mk]) if $options[:mk]
    resign_apks(KEY_REF_APKS[:rk], $options[:rk]) if $options[:rk]
end
