require "gemstash"
require "stringio"
require "zlib"

module Gemstash
  # Builds a Marshal'ed and GZipped array of arrays containing specs as:
  # [name, Gem::Version, platform]
  class SpecsBuilder
    attr_reader :result

    # Used for the /private/specs.4.8.gz endpoint. Fetches non-prerelease,
    # indexed private gems.
    def self.all
      new.build
    end

    # Used for the /private/prerelease_specs.4.8.gz endpoint. Fetches
    # prerelease, indexed private gems.
    def self.prerelease
      new(prerelease: true).build
    end

    def self.invalidate_stored
      storage = Gemstash::Storage.for("private").for("specs_collection")
      storage.resource("specs.4.8.gz").delete
      storage.resource("prerelease_specs.4.8.gz").delete
    end

    def initialize(prerelease: false)
      @prerelease = prerelease
    end

    def build
      fetch_from_storage
      return result if result
      fetch_versions
      marshal
      gzip
      store_result
      result
    end

  private

    def storage
      @storage ||= Gemstash::Storage.for("private").for("specs_collection")
    end

    def fetch_resource
      if @prerelease
        storage.resource("prerelease_specs.4.8.gz")
      else
        storage.resource("specs.4.8.gz")
      end
    end

    def fetch_from_storage
      specs = fetch_resource
      return unless specs.exist?
      @result = specs.load.content
    rescue
      # On the off-chance of a race condition between specs.exist? and specs.load
      @result = nil
    end

    def fetch_versions
      @versions = Gemstash::DB::Version.for_spec_collection(prerelease: @prerelease).map(&:to_spec)
    end

    def marshal
      @marshal ||= Marshal.dump(@versions)
    end

    def gzip
      @result ||= begin
        output = StringIO.new
        gz = Zlib::GzipWriter.new(output)

        begin
          gz.write(@marshal)
        ensure
          gz.close
        end

        output.string
      end
    end

    def store_result
      fetch_resource.save(@result)
    end
  end
end
