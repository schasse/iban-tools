module IBANTools
  class Conversion

    def self.local2iban(country_code, data)
      config = load_config country_code

      bban = config.map do |key, values|
        d = data[key.to_sym].dup
        ret = [values].flatten.map do |value|
          l = bban_format_length(value)
          r = bban_format_to_format_string(value) % bban_format_cast(value, d[0..(l-1)])
          d[0..(l-1)] = ''
          r
        end.join('')
        # "%05s" % "a" -> "    a" and not "0000a"
        ret.gsub(/ /, '0')
      end.join('')

      check_digits = "%02d" % checksum(country_code, bban)

      IBAN.new "#{country_code}#{check_digits}#{bban}"
    end

    def self.iban2local(country_code, bban)
      config = load_config country_code

      local = {}
      config.each do |key, values|
        local[key.to_sym] = [values].flatten.map do |value|
          regexp = /^#{bban_format_to_regexp(value)}/
          ret = bban.scan(regexp).first
          bban.sub! regexp, ''
          ret
        end.join('')
        local[key.to_sym].sub!(/^0+/, '')
        local[key.to_sym] = '0' if local[key.to_sym] == ''
      end
      local
    end

    def self.iban2bic(country_code, bban)
      require 'banking_data'
      local = iban2local(country_code, bban)
      country = country_code.downcase.to_sym
      blz_attribute =
        if country.to_s.upcase == 'DE'
          :blz
        else
          :bank_code
        end
      if local.respond_to?(:[]) && local[blz_attribute]
        bic =
          BankingData::Bank.where(locale: country, blz: local[blz_attribute]).
          only(:bic).
          flatten.
          first
        bic
      end
    rescue LoadError
      require 'logger'
      logger = Logger.new(STDOUT)
      logger.warn 'You have tried to convert an IBAN to BIC without ' +
                  'installing the `banking_data` gem'
      nil
    end

    private

    BBAN_REGEXP = /^(\d+)(!?)([nace])$/

    def self.bban_format_length(format)
      if format =~ BBAN_REGEXP
        return $1.to_i
      else
        raise ArgumentError, "#{format} is not a valid bban format"
      end
    end

    def self.bban_format_to_format_string(format)
      if format =~ BBAN_REGEXP
        if $3 == "e"
          return " " * $1.to_i
        end
        format = '%0' + $1
        format += case $3
                 when 'n' then 'd'
                 when 'a' then 's'
                 when 'c' then 's'
                 end
        return format
      else
        raise ArgumentError, "#{format} is not a valid bban format"
      end
    end

    def self.bban_format_cast(format, value)
      if format =~ BBAN_REGEXP
        if $3 == "n"
          return value.to_i
        else
          return value
        end
      else
        raise ArgumentError, "#{format} is not a valid bban format"
      end
    end

    def self.bban_format_to_regexp(format)
      if format =~ BBAN_REGEXP
        regexp = case $3
                 when 'n' then '[0-9]'
                 when 'a' then '[A-Z]'
                 when 'c' then '[a-zA-Z0-9]'
                 when 'e' then '[ ]'
                 end
        regexp += '{'
        unless $2 == '!'
          regexp += ','
        end
        regexp += $1 + '}'
        return regexp
      else
        raise ArgumentError, "#{format} is not a valid bban format"
      end
    end

    def self.load_config(country_code)
      default_config = YAML.
        load_file(File.join(File.dirname(__FILE__), 'conversion_rules.yml'))
      unless default_config.key?(country_code)
        raise ArgumentError, "Country code #{country_code} not availble"
      end
      default_config[country_code]
    end

    def self.checksum(country_code, bban)
      97 - (IBAN.new("#{country_code}00#{bban}").numerify.to_i % 97) + 1
    end
  end
end
