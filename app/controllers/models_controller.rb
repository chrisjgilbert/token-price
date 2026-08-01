class ModelsController < ApplicationController
  def index
    @providers = Provider.order(:name).to_a

    # The pricing-family tab. Every param the category governs (sort keys,
    # defaults, SEO) is read off it, so a new tab is a registry + route change.
    @category = ModelCategory.for(params[:category])

    @provider_slugs = Array(params[:providers]).map(&:to_s) & @providers.map(&:slug)

    @sort = params[:sort].presence_in(@category.sorts) || @category.default_sort
    @dir = params[:dir].presence_in(%w[asc desc]) || @category.default_dir

    # Capped so a pathological query can't burn CPU in the fuzzy matcher.
    @query = params[:q].to_s.strip[0, 100]

    # modality_class is derived in Ruby, not a column. Validate the param against
    # the full known class set (no query) so it can ride the etag; the facet of
    # classes actually present is derived from the loaded rows after the 304
    # check, so a conditional hit pays for no extra load.
    # Scope the modality facet to classes that belong to THIS tab, so a stale
    # inbound link like /?modality=image_generation (image moved to its own tab)
    # is ignored rather than filtering the language rows down to an empty table.
    @modalities = (Array(params[:modality]).map(&:to_s) & ModalityClass::LABELS.keys.map(&:to_s))
      .select { |mc| @category.member?(mc.to_sym) }

    # Per-category SEO the view reads for <title>, meta description, and canonical
    # (the tab is an indexable URL, not a query permutation, so each owns its own).
    @page_title = @category.title
    @page_description = @category.meta_description
    @canonical_url = send("#{@category.path_name}_url")

    # Conditional GET. The page varies by every filter/sort param AND the category
    # tab, so they MUST ride in the etag — otherwise a conditional request for one
    # view would 304 off another's cache (a tab off a sibling tab included).
    # last_modified spans the catalog AND the market events the hero renders, so
    # editing a market event busts the cache instead of serving a stale hero.
    # Renders 304 on a match.
    return if catalog_fresh?(etag: [ :index, @category.slug, @provider_slugs.sort, @sort, @dir, @query, @modalities.sort ],
      last_modified: helpers.timeline_last_modified)

    listing = ModelListing.new(category: @category, sort: @sort, dir: @dir,
      provider_slugs: @provider_slugs, query: @query, modalities: @modalities)
    @models = listing.models
    @modality_classes = listing.modality_classes
    @category_counts = ModelCategory.counts

    # Hero content (loaded once; lives outside the Turbo Frame).
    # Only loaded on full-page renders, not on Turbo Frame refreshes.
    unless request.headers["Turbo-Frame"] == "models"
      @recent_events = MarketEvent.published.recent_first.limit(5).to_a
      @providers_count = Provider.count
    end
  end

  def show
    @model = AiModel.includes(:provider, :price_points).find_by!(slug: params[:id])

    # Conditional GET keyed on this model's latest price write (updated_at, not
    # effective_on) so a same-day in-place price correction still busts the cache,
    # AND on the model row's own updated_at so an edit to non-price fields the page
    # renders (the modality signature, description, …) busts it too. Both ride the
    # ETag, so an If-None-Match alone invalidates.
    price_updated_at = @model.current_price&.updated_at
    freshness = [ price_updated_at, @model.updated_at ].compact.max
    return if catalog_fresh?(etag: [ :model_show, @model.slug, price_updated_at, @model.updated_at ],
      last_modified: freshness)

    # The freshness instant the page surfaces to readers — the same value the
    # conditional GET is keyed on, so "data updated" can't claim a time newer
    # than the one the cache would serve.
    @last_updated = freshness
    @price_points = @model.price_points.chronological.to_a
    # Present only when the model is listed (priced); nil otherwise, so the view's
    # extra-billing section reads off a real catalog entry or renders nothing.
    @catalog_entry = PriceCatalog.model(@model.slug)
    @related = AiModel.listed.where(provider: @model.provider)
      .where.not(id: @model.id)
      .includes(:price_points, :provider).by_release.limit(4)
  end
end
