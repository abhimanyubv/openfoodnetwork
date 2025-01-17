require_relative 'boot'

require 'rails/all'
require_relative "../lib/open_food_network/i18n_config"

if defined?(Bundler)
  # If you precompile assets before deploying to production, use this line
  Bundler.require(*Rails.groups(:assets => %w(development test)))
  # If you want your assets lazily compiled in production, use this line
  # Bundler.require(:default, :assets, Rails.env)
end

module Openfoodnetwork
  class Application < Rails::Application

    config.to_prepare do
      # Load application's model / class decorators
      Dir.glob(File.join(File.dirname(__FILE__), "../app/**/*_decorator*.rb")) do |c|
        Rails.configuration.cache_classes ? require(c) : load(c)
      end

      # Load application's view overrides
      Dir.glob(File.join(File.dirname(__FILE__), "../app/overrides/*.rb")) do |c|
        Rails.configuration.cache_classes ? require(c) : load(c)
      end
    end

    # Settings dependent on locale
    #
    # We need to set this config before the promo environment gets loaded and
    # after the spree environment gets loaded...
    # This is because Spree uses `Spree::Config` while evaluating classes :scream:
    #
    # https://github.com/spree/spree/blob/2-0-stable/core/app/models/spree/calculator/per_item.rb#L6
    #
    # TODO: move back to spree initializer once we upgrade to a more recent version
    #       of Spree
    initializer 'ofn.spree_locale_settings', before: 'spree.promo.environment' do |app|
      Spree::Config['checkout_zone'] = ENV['CHECKOUT_ZONE']
      Spree::Config['currency'] = ENV['CURRENCY']
      if Spree::Country.table_exists?
        country = Spree::Country.find_by_iso(ENV['DEFAULT_COUNTRY_CODE'])
        Spree::Config['default_country_id'] = country.id if country.present?
      else
        Spree::Config['default_country_id'] = 12  # Australia
      end
    end

    # Register Spree calculators
    initializer 'spree.register.calculators' do |app|
      app.config.spree.calculators.shipping_methods = [
        Spree::Calculator::FlatPercentItemTotal,
        Spree::Calculator::FlatRate,
        Spree::Calculator::FlexiRate,
        Spree::Calculator::PerItem,
        Spree::Calculator::PriceSack,
        Calculator::Weight
      ]

      app.config.spree.calculators.add_class('enterprise_fees')
      config.spree.calculators.enterprise_fees = [
        Calculator::FlatPercentPerItem,
        Spree::Calculator::FlatRate,
        Spree::Calculator::FlexiRate,
        Spree::Calculator::PerItem,
        Spree::Calculator::PriceSack,
        Calculator::Weight
      ]
      app.config.spree.calculators.add_class('payment_methods')
      config.spree.calculators.payment_methods = [
        Spree::Calculator::FlatPercentItemTotal,
        Spree::Calculator::FlatRate,
        Spree::Calculator::FlexiRate,
        Spree::Calculator::PerItem,
        Spree::Calculator::PriceSack
      ]
    end

    # Every splitter (except Base splitter) will split the order in multiple packages
    #   Each package will generate a separate shipment in the order
    #   Base splitter does not split the packages
    #   So, because in OFN we have locked orders to have only one shipment,
    #     we must use this splitter and no other
    initializer "spree.register.stock_splitters" do |app|
      app.config.spree.stock_splitters = [
        Spree::Stock::Splitter::Base
      ]
    end

    # Register Spree payment methods
    initializer "spree.gateway.payment_methods", :after => "spree.register.payment_methods" do |app|
      app.config.spree.payment_methods << Spree::Gateway::Migs
      app.config.spree.payment_methods << Spree::Gateway::Pin
      app.config.spree.payment_methods << Spree::Gateway::StripeConnect
    end

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Custom directories with classes and modules you want to be autoloadable.
    config.autoload_paths += %W(
      #{config.root}/app/models/concerns
      #{config.root}/app/presenters
      #{config.root}/app/jobs
    )

    config.paths["config/routes"] = %w(
      config/routes/api.rb
      config/routes.rb
      config/routes/admin.rb
      config/routes/spree.rb
    ).map { |relative_path| Rails.root.join(relative_path) }

    # Only load the plugins named here, in the order given (default is alphabetical).
    # :all can be used as a placeholder for all plugins not explicitly named.
    # config.plugins = [ :exception_notification, :ssl_requirement, :all ]

    # Activate observers that should always be running.
    # config.active_record.observers = :cacher, :garbage_collector, :forum_observer

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    config.time_zone = 'UTC'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    config.i18n.default_locale = OpenFoodNetwork::I18nConfig.default_locale
    config.i18n.available_locales = OpenFoodNetwork::I18nConfig.available_locales
    I18n.locale = config.i18n.locale = config.i18n.default_locale

    # Setting this to true causes a performance regression in Rails 3.2.17
    # When we're on a version with the fix below, we can set it to true
    # https://github.com/svenfuchs/i18n/issues/230
    I18n.config.enforce_available_locales = false

    # Configure the default encoding used in templates for Ruby 1.9.
    config.encoding = "utf-8"

    # Configure sensitive parameters which will be filtered from the log file.
    config.filter_parameters += [:password]

    # Enable the asset pipeline
    config.assets.enabled = true

    # Version of your assets, change this if you want to expire all your assets
    config.assets.version = '1.2'

    config.sass.load_paths += [
      "#{Gem.loaded_specs['foundation-rails'].full_gem_path}/vendor/assets/stylesheets/foundation/components",
      "#{Gem.loaded_specs['foundation-rails'].full_gem_path}/vendor/assets/stylesheets/foundation/"
    ]

    # css and js files other than application.* are not precompiled by default
    # Instead, they must be explicitly included below
    # http://stackoverflow.com/questions/8012434/what-is-the-purpose-of-config-assets-precompile
    config.assets.initialize_on_precompile = true
    config.assets.precompile += ['iehack.js']
    config.assets.precompile += ['admin/all.css', 'admin/*.js', 'admin/**/*.js']
    config.assets.precompile += ['web/all.css', 'web/all.js']
    config.assets.precompile += ['darkswarm/all.css', 'darkswarm/all.js']
    config.assets.precompile += ['mail/all.css']
    config.assets.precompile += ['shared/*']
    config.assets.precompile += ['qz/*']

    config.active_support.escape_html_entities_in_json = true
  end
end
