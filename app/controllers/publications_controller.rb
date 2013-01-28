class PublicationsController < DocumentsController
  class OldPublicationesqueDecorator < SimpleDelegator
    def documents
      PublicationesquePresenter.decorate(__getobj__.documents)
    end
  end
  class PublicationesqueDecorator < SimpleDelegator
    def search
      __getobj__.publication_search.results
    end
    def documents
      PublicationesquePresenter.decorate(__getobj__.publication_search.results)
    end
    def count
      search.results.count
    end
    def current_page
      search.current_page
    end
    def num_pages
      search.total_pages
    end
    def total_count
      search.total_entries
    end
    def last_page?
      search.last_page?
    end
    def first_page?
      search.first_page?
    end
  end

  def index
    params[:page] ||= 1
    params[:direction] ||= "before"

    clean_malformed_params_array(:topics)
    clean_malformed_params_array(:departments)

    expire_on_next_scheduled_publication(scheduled_publications)

    @es = params[:test] || nil
    if @es == "es"
      search = Whitehall::DocumentSearch.new(params)
      @filter = PublicationesqueDecorator.new(search)
    else
      document_filter = Whitehall::DocumentFilter.new(all_publications, params)
      @filter = OldPublicationesqueDecorator.new(document_filter)
    end

    respond_to do |format|
      format.html
      format.json do
        render json: PublicationFilterJsonPresenter.new(@filter)
      end
      format.atom do
        @publications = @filter.documents.sort_by(&:public_timestamp).reverse
        # TODO fix atom feed in ES
        # @publications = @filter.documents
      end
    end
  end

  def show
    @related_policies = @document.statistics? ? [] : @document.published_related_policies
    set_slimmer_organisations_header(@document.organisations)
  end

private

  def all_publications
    Publicationesque.published.includes(:document, :organisations, :attachments, response: :attachments)
  end

  def scheduled_publications
    unfiltered = Publicationesque.scheduled.order("scheduled_publication asc")
    Whitehall::DocumentFilter.new(unfiltered, params.except(:direction)).documents
    # @scheduled_publications = Publicationesque.scheduled.order("scheduled_publication asc")
  end

  def document_class
    Publication
  end
end
