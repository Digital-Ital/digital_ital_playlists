module MusicMetadata
  SourceResult = Struct.new(
    :source,
    :claims,
    :metadata,
    :error,
    :skipped,
    :outcome,
    :outcome_reason,
    keyword_init: true
  ) do
    def successful?
      error.blank? && !skipped?
    end

    def skipped?
      skipped == true
    end
  end
end
