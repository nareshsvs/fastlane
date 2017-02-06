module Match
  class Utils
    def self.import(item_path, keychain, cert_password)
      # Existing code expects that a keychain name will be expanded into a default path to Libary/Keychains
      # in the user's home directory. However, this will not allow the user to pass an absolute path
      # for the keychain value
      #
      # So, if the passed value can't be resolved as a file in Library/Keychains, just use it as-is
      # as the keychain path.
      #
      # We need to expand each path because File.exist? won't handle directories including ~ properly
      #
      # We also try to append `-db` at the end of the file path, as with Sierra the default Keychain name
      # has changed for some users: https://github.com/fastlane/fastlane/issues/5649
      #
      keychain_paths = [
        File.join(Dir.home, 'Library', 'Keychains', keychain),
        File.join(Dir.home, 'Library', 'Keychains', "#{keychain}-db"),
        keychain,
        "#{keychain}-db"
      ].map { |path| File.expand_path(path) }

      keychain_path = keychain_paths.find { |path| File.exist?(path) }
      
      puts('keychain_path'+keychain_path)

      UI.user_error!("Could not locate the provided keychain. Tried:\n\t#{keychain_paths.join("\n\t")}") unless keychain_path
      if cert_password.length > 0 then
        command = "security import #{item_path.shellescape} -k #{keychain_path.shellescape} -P #{cert_password.shellescape}"
      else
        puts 'Importing certificates without password'
        command = "security import #{item_path.shellescape} -k ~/Library/Keychains/#{keychain_path.shellescape} "
      end


      #command = "security import #{item_path.shellescape} -k #{keychain_path.shellescape}"
      command << " -T /usr/bin/codesign" # to not be asked for permission when running a tool like `gym`
      command << " -T /usr/bin/security"
      command << " &> /dev/null" unless $verbose

      Helper.backticks(command, print: $verbose)
    end

    # Fill in an environment variable, ready to be used in _xcodebuild_
    def self.fill_environment(key, value)
      UI.important "Setting environment variable '#{key}' to '#{value}'" if $verbose
      ENV[key] = value
    end

    def self.environment_variable_name(app_identifier: nil, type: nil, platform: :ios)
      base_environment_variable_name(app_identifier: app_identifier, type: type, platform: platform).join("_")
    end

    def self.environment_variable_name_team_id(app_identifier: nil, type: nil, platform: :ios)
      (base_environment_variable_name(app_identifier: app_identifier, type: type, platform: platform) + ["team-id"]).join("_")
    end

    def self.environment_variable_name_profile_name(app_identifier: nil, type: nil, platform: :ios)
      (base_environment_variable_name(app_identifier: app_identifier, type: type, platform: platform) + ["profile-name"]).join("_")
    end

    def self.get_cert_info(cer_certificate_path)
      command = "openssl x509 -inform der -in #{cer_certificate_path.shellescape} -subject -dates -noout"
      command << " &" # start in separate process
      output = Helper.backticks(command, print: $verbose)

      # openssl output:
      # subject= /UID={User ID}/CN={Certificate Name}/OU={Certificate User}/O={Organisation}/C={Country}\n
      # notBefore={Start datetime}\n
      # notAfter={End datetime}
      cert_info = output.gsub(/\s*subject=\s*/, "").tr("/", "\n")
      out_array = cert_info.split("\n")
      openssl_keys_to_readable_keys = {
           'UID' => 'User ID',
           'CN' => 'Common Name',
           'OU' => 'Organisation Unit',
           'O' => 'Organisation',
           'C' => 'Country',
           'notBefore' => 'Start Datetime',
           'notAfter' => 'End Datetime'
       }

      return out_array.map { |x| x.split(/=+/) if x.include? "=" }
                      .compact
                      .map { |k, v| [openssl_keys_to_readable_keys.fetch(k, k), v] }
    rescue => ex
      UI.error(ex)
      return {}
    end

    def self.base_environment_variable_name(app_identifier: nil, type: nil, platform: :ios)
      if platform.to_s == :ios.to_s
        ["sigh", app_identifier, type] # We keep the ios profiles without the platform for backwards compatibility
      else
        ["sigh", app_identifier, type, platform.to_s]
      end
    end
  end
end
