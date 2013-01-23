class Whitehall::DocumentSearch
  attr_reader :page, :direction, :date

  def initialize(params = {})
    @params = params
    @per_page = params[:per_page] || 20
    @page = params[:page]
    @direction = params[:direction]
    @date = parse_date(@params[:date]) if @params[:date].present?
    @keywords = params[:keywords]

    @announcement_type = params[:announcement_type]
    @people_ids = @params[:people_id]
  end

  def keyword_search(search)
    if @keywords.present?
      search.query do |query|
        query.string @keywords
      end
    else
      search.query { all }
    end
  end

  def filter_topics(search)
    if selected_topics.any?
      search.filter :term, topics: selected_topics.map(&:id)
    end
  end

  def filter_organisations(search)
    if selected_organisations.any?
      search.filter :term, organisations: selected_organisations.map(&:id)
    end
  end

  def filter_by_format(search)
    if @format.present?
      search.filter :term, format: @format
    end
  end


  def filter_by_announcement_type(search)
    case @announcement_type
    when "speech"
      speech_ids = [SpeechType::Transcript, SpeechType::DraftText, SpeechType::SpeakingNotes].map(&:id)
      search.filter :term, speech_type: speech_ids
    when "statement"
      statement_ids = [SpeechType::WrittenStatement, SpeechType::OralStatement].map(&:id)
      search.filter :term, speech_type: statement_ids
    when "fatality_notice"
      @format = 'fatality_notice'
      filter_by_format(search)
    else
      search.filter :or, [{term: {format: "speech"}}, {term: {format: "news_article"}}, {term: {format: "fatality_notice"}}]
    end
  end

  def filter_by_publication_type(search)
    if selected_publication_filter_option
      publication_ids = selected_publication_filter_option.publication_types.map(&:id)
      if selected_publication_filter_option.edition_types.any?
        edition_types = selected_publication_filter_option.edition_types
        format = edition_types.first.underscore #TODO: refactor so only one type is selected
        search.filter :or, [{term: {format: format}}, {term: {publication_type: publication_ids}}]
      else
        search.filter :term, publication_type: publication_ids
      end
    else
      search.filter :or, [{term: {format: "publication"}}, {term: {format: "statistical_data_set"}}, {term: {format: "consultation"}}]
    end
  end

  def filter_by_people(search)
    if @people_ids.present? && @people_ids != ["all"]
      search.filter :term, people: @people_ids
    end
  end

  def filter_date_and_sort(search)
    if @date.present? && @direction.present?
      case @direction
      when "before"
        search.filter :range, public_timestamp: {to: @date - 1.day}
        search.sort { by :public_timestamp, :desc }
      when "after"
        search.filter :range, public_timestamp: {from: @date }
        search.sort { by :public_timestamp}
      end
    end
  end

  def paginate(search)
    search.size @per_page
    search.from( @page.to_i <= 1 ? 0 : (@per_page.to_i * (@page.to_i-1)) )
  end

  def announcement_search
    @results ||= Tire.search Whitehall.government_search_index_name, load: {include: [:document, :organisations]} do |search|
      keyword_search(search)
      filter_by_announcement_type(search)
      filter_topics(search)
      filter_organisations(search)
      filter_by_people(search)
      filter_date_and_sort(search)
      paginate(search)
    end
  end

  def publication_search
    @results ||= Tire.search Whitehall.government_search_index_name, load: {include: [:document, :organisations, :attachments, response: :attachments]} do |search|
      keyword_search(search)
      filter_by_publication_type(search)
      filter_topics(search)
      filter_organisations(search)
      filter_date_and_sort(search)
      paginate(search)
    end
  end

  def policy_search
    @results ||= Tire.search Whitehall.government_search_index_name, load: {include: [:document, :organisations]} do |search|
      keyword_search(search)
      @format = "policy"
      filter_by_format(search)
      filter_topics(search)
      filter_organisations(search)
      filter_date_and_sort(search)
      paginate(search)
    end
  end

  def selected_topics
    find_by_slug(Topic, @params[:topics])
  end

  def selected_organisations
    find_by_slug(Organisation, @params[:departments])
  end

  def selected_publication_filter_option
    filter_option = @params[:publication_filter_option] || @params[:publication_type]
    Whitehall::PublicationFilterOption.find_by_slug(filter_option)
  end

  def selected_announcement_type_option
    @announcement_type
  end

  def selected_people_option
    @people_ids
  end

  def keywords
    if @keywords.present?
      @keywords.strip.split(/\s+/)
    else
      []
    end
  end

  def parse_date(date)
    Date.parse(date)
    rescue ArgumentError => e
      if e.message[/invalid date/]
        return nil
      else
        raise e
    end
  end

  private

  def find_by_slug(klass, slugs)
    @selected ||= {}
    @selected[klass] ||= if slugs.present? && !slugs.include?("all")
      klass.where(slug: slugs)
    else
      []
    end
  end

end