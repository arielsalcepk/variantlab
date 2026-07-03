# frozen_string_literal: true

class HomeController < StoreController
  helper "spree/products"
  respond_to :html

  def index
    @searcher = build_searcher(params.merge(include_images: true))
    @products = @searcher.retrieve_products

    # With limited products, show them in multiple sections
    @featured_products = @products
    @collection_products = @products
    @cta_collection_products = @products[0..1]
    @new_arrivals = @products
  end
end
