module MusicMetadata
  SourceResult = Struct.new(:source, :claims, :metadata, :error, :skipped, keyword_init: true) do
    def successful?
      error.blank? && !skipped?
    end

    def skipped?
      skipped == true
    end
  end
end
