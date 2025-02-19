# frozen_string_literal: true

require "fileutils"
require "digest/md5"
require "rails/version" unless defined?(Rails::VERSION)
require "open-uri"
require "uri"
require "rails/generators"
require "active_support/core_ext/array/extract_options"

module Rails
  module Generators
    class AppBase < Base # :nodoc:
      include Database
      include AppName

      attr_accessor :rails_template
      add_shebang_option!

      argument :app_path, type: :string

      def self.strict_args_position
        false
      end

      def self.add_shared_options_for(name)
        class_option :template,            type: :string, aliases: "-m",
                                           desc: "Path to some #{name} template (can be a filesystem path or URL)"

        class_option :database,            type: :string, aliases: "-d", default: "sqlite3",
                                           desc: "Preconfigure for selected database (options: #{DATABASES.join('/')})"

        class_option :skip_git,            type: :boolean, aliases: "-G", default: false,
                                           desc: "Skip .gitignore file"

        class_option :skip_keeps,          type: :boolean, default: false,
                                           desc: "Skip source control .keep files"

        class_option :skip_action_mailer,  type: :boolean, aliases: "-M",
                                           default: false,
                                           desc: "Skip Action Mailer files"

        class_option :skip_action_mailbox, type: :boolean, default: false,
                                           desc: "Skip Action Mailbox gem"

        class_option :skip_action_text,    type: :boolean, default: false,
                                           desc: "Skip Action Text gem"

        class_option :skip_active_record,  type: :boolean, aliases: "-O", default: false,
                                           desc: "Skip Active Record files"

        class_option :skip_active_job,     type: :boolean, default: false,
                                           desc: "Skip Active Job"

        class_option :skip_active_storage, type: :boolean, default: false,
                                           desc: "Skip Active Storage files"

        class_option :skip_action_cable,   type: :boolean, aliases: "-C", default: false,
                                           desc: "Skip Action Cable files"

        class_option :skip_sprockets,      type: :boolean, aliases: "-S", default: false,
                                           desc: "Skip Sprockets files"

        class_option :skip_javascript,     type: :boolean, aliases: "-J", default: name == "plugin",
                                           desc: "Skip JavaScript files"

        class_option :skip_hotwire,        type: :boolean, default: false,
                                           desc: "Skip Hotwire integration"

        class_option :skip_jbuilder,       type: :boolean, default: false,
                                           desc: "Skip jbuilder gem"

        class_option :skip_test,           type: :boolean, aliases: "-T", default: false,
                                           desc: "Skip test files"

        class_option :skip_system_test,    type: :boolean, default: false,
                                           desc: "Skip system test files"

        class_option :skip_bootsnap,       type: :boolean, default: false,
                                           desc: "Skip bootsnap gem"

        class_option :dev,                 type: :boolean, default: false,
                                           desc: "Set up the #{name} with Gemfile pointing to your Rails checkout"

        class_option :edge,                type: :boolean, default: false,
                                           desc: "Set up the #{name} with Gemfile pointing to Rails repository"

        class_option :main,                type: :boolean, default: false, aliases: "--master",
                                           desc: "Set up the #{name} with Gemfile pointing to Rails repository main branch"

        class_option :rc,                  type: :string, default: nil,
                                           desc: "Path to file containing extra configuration options for rails command"

        class_option :no_rc,               type: :boolean, default: false,
                                           desc: "Skip loading of extra configuration options from .railsrc file"

        class_option :help,                type: :boolean, aliases: "-h", group: :rails,
                                           desc: "Show this help message and quit"
      end

      def initialize(*)
        @gem_filter = lambda { |gem| true }
        super
      end

    private
      def gemfile_entries # :doc:
        [rails_gemfile_entry,
         database_gemfile_entry,
         web_server_gemfile_entry,
         assets_gemfile_entry,
         webpacker_gemfile_entry,
         javascript_gemfile_entry,
         jbuilder_gemfile_entry,
         psych_gemfile_entry,
         cable_gemfile_entry].flatten.find_all(&@gem_filter)
      end

      def builder # :doc:
        @builder ||= begin
          builder_class = get_builder_class
          builder_class.include(ActionMethods)
          builder_class.new(self)
        end
      end

      def build(meth, *args) # :doc:
        builder.public_send(meth, *args) if builder.respond_to?(meth)
      end

      def create_root # :doc:
        valid_const?

        empty_directory "."
        FileUtils.cd(destination_root) unless options[:pretend]
      end

      def apply_rails_template # :doc:
        apply rails_template if rails_template
      rescue Thor::Error, LoadError, Errno::ENOENT => e
        raise Error, "The template [#{rails_template}] could not be loaded. Error: #{e}"
      end

      def set_default_accessors! # :doc:
        self.destination_root = File.expand_path(app_path, destination_root)
        self.rails_template = \
          case options[:template]
          when /^https?:\/\//
            options[:template]
          when String
            File.expand_path(options[:template], Dir.pwd)
          else
            options[:template]
          end
      end

      def database_gemfile_entry # :doc:
        return [] if options[:skip_active_record]
        gem_name, gem_version = gem_for_database
        GemfileEntry.version gem_name, gem_version,
                            "Use #{options[:database]} as the database for Active Record"
      end

      def web_server_gemfile_entry # :doc:
        comment = "Use Puma as the app server"
        GemfileEntry.new("puma", "~> 5.0", comment)
      end

      def include_all_railties? # :doc:
        [
          options.values_at(
            :skip_active_record,
            :skip_action_mailer,
            :skip_test,
            :skip_sprockets,
            :skip_action_cable,
            :skip_active_job
          ),
          skip_active_storage?,
          skip_action_mailbox?,
          skip_action_text?
        ].flatten.none?
      end

      def comment_if(value) # :doc:
        question = "#{value}?"

        comment =
          if respond_to?(question, true)
            send(question)
          else
            options[value]
          end

        comment ? "# " : ""
      end

      def keeps? # :doc:
        !options[:skip_keeps]
      end

      def sqlite3? # :doc:
        !options[:skip_active_record] && options[:database] == "sqlite3"
      end

      def skip_active_storage? # :doc:
        options[:skip_active_storage] || options[:skip_active_record]
      end

      def skip_action_mailbox? # :doc:
        options[:skip_action_mailbox] || skip_active_storage?
      end

      def skip_action_text? # :doc:
        options[:skip_action_text] || skip_active_storage?
      end

      def skip_dev_gems? # :doc:
        options[:skip_dev_gems]
      end

      class GemfileEntry < Struct.new(:name, :version, :comment, :options, :commented_out)
        def initialize(name, version, comment, options = {}, commented_out = false)
          super
        end

        def self.github(name, github, branch = nil, comment = nil)
          if branch
            new(name, nil, comment, github: github, branch: branch)
          else
            new(name, nil, comment, github: github)
          end
        end

        def self.version(name, version, comment = nil)
          new(name, version, comment)
        end

        def self.path(name, path, comment = nil)
          new(name, nil, comment, path: path)
        end

        def version
          version = super

          if version.is_a?(Array)
            version.join('", "')
          else
            version
          end
        end
      end

      def rails_gemfile_entry
        if options.dev?
          [
            GemfileEntry.path("rails", Rails::Generators::RAILS_DEV_PATH)
          ]
        elsif options.edge?
          edge_branch = Rails.gem_version.prerelease? ? "main" : [*Rails.gem_version.segments.first(2), "stable"].join("-")
          [
            GemfileEntry.github("rails", "rails/rails", edge_branch)
          ]
        elsif options.main?
          [
            GemfileEntry.github("rails", "rails/rails", "main")
          ]
        else
          [GemfileEntry.version("rails",
                            rails_version_specifier,
                            "Bundle edge Rails instead: gem 'rails', github: 'rails/rails', branch: 'main'")]
        end
      end

      def rails_version_specifier(gem_version = Rails.gem_version)
        if gem_version.segments.size == 3 || gem_version.release.segments.size == 3
          # ~> 1.2.3
          # ~> 1.2.3.pre4
          "~> #{gem_version}"
        else
          # ~> 1.2.3, >= 1.2.3.4
          # ~> 1.2.3, >= 1.2.3.4.pre5
          patch = gem_version.segments[0, 3].join(".")
          ["~> #{patch}", ">= #{gem_version}"]
        end
      end

      # This "npm-ifies" the current version number
      # With npm, versions such as "5.0.0.rc1" or "5.0.0.beta1.1" are not compliant with its
      # versioning system, so they must be transformed to "5.0.0-rc1" and "5.0.0-beta1-1" respectively.
      #
      # "5.0.1"     --> "5.0.1"
      # "5.0.1.1"   --> "5.0.1-1" *
      # "5.0.0.rc1" --> "5.0.0-rc1"
      #
      # * This makes it a prerelease. That's bad, but we haven't come up with
      # a better solution at the moment.
      def npm_version
        if options.edge? || options.main? || options.dev?
          # TODO: ideally this would read from Github
          # https://github.com/rails/rails/blob/main/actioncable/app/assets/javascripts/action_cable.js
          # https://github.com/rails/rails/blob/main/activestorage/app/assets/javascripts/activestorage.js
          # https://github.com/rails/rails/tree/main/actionview/app/assets/javascripts -> not clear where the output file is
          "latest"
        else
          Rails.version.gsub(/\./).with_index { |s, i| i >= 2 ? "-" : s }
        end
      end

      def assets_gemfile_entry
        return [] if options[:skip_sprockets]

        GemfileEntry.version("sass-rails", ">= 6", "Use SCSS for stylesheets")
      end

      def webpacker_gemfile_entry
        if options[:webpack]
          GemfileEntry.version "webpacker", "~> 6.0.0.rc.5", "Transpile app-like JavaScript. Read more: https://github.com/rails/webpacker"
        else
          []
        end
      end

      def jbuilder_gemfile_entry
        return [] if options[:skip_jbuilder]
        comment = "Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder"
        GemfileEntry.new "jbuilder", "~> 2.7", comment, {}, options[:api]
      end

      def javascript_gemfile_entry
        importmap_rails_entry =
          GemfileEntry.version("importmap-rails", ">= 0.3.4", "Manage modern JavaScript using ESM without transpiling or bundling")

        turbo_rails_entry =
          GemfileEntry.version("turbo-rails", ">= 0.7.4", "Hotwire's SPA-like page accelerator. Read more: https://turbo.hotwired.dev")

        stimulus_rails_entry =
          GemfileEntry.version("stimulus-rails", ">= 0.3.9", "Hotwire's modest JavaScript framework for the HTML you already have. Read more: https://stimulus.hotwired.dev")

        if options[:skip_javascript]
          []
        elsif options[:skip_hotwire]
          [ importmap_rails_entry ]
        else
          [ importmap_rails_entry, turbo_rails_entry, stimulus_rails_entry ]
        end
      end

      def psych_gemfile_entry
        return [] unless defined?(Rubinius)

        comment = "Use Psych as the YAML engine, instead of Syck, so serialized " \
                  "data can be read safely from different rubies (see http://git.io/uuLVag)"
        GemfileEntry.new("psych", "~> 2.0", comment, platforms: :rbx)
      end

      def cable_gemfile_entry
        return [] if options[:skip_action_cable]
        comment = "Use Redis adapter to run Action Cable in production"
        gems = []
        gems << GemfileEntry.new("redis", "~> 4.0", comment, {}, true)
        gems
      end

      def bundle_command(command, env = {})
        say_status :run, "bundle #{command}"

        # We are going to shell out rather than invoking Bundler::CLI.new(command)
        # because `rails new` loads the Thor gem and on the other hand bundler uses
        # its own vendored Thor, which could be a different version. Running both
        # things in the same process is a recipe for a night with paracetamol.
        #
        # Thanks to James Tucker for the Gem tricks involved in this call.
        _bundle_command = Gem.bin_path("bundler", "bundle")

        require "bundler"
        Bundler.with_original_env do
          exec_bundle_command(_bundle_command, command, env)
        end
      end

      def exec_bundle_command(bundle_command, command, env)
        full_command = %Q["#{Gem.ruby}" "#{bundle_command}" #{command}]
        if options[:quiet]
          system(env, full_command, out: File::NULL)
        else
          system(env, full_command)
        end
      end

      def bundle_install?
        !(options[:skip_bundle] || options[:pretend])
      end

      def webpack_install?
        options[:webpack]
      end

      def importmap_install?
        !(options[:skip_javascript] || options[:webpack])
      end

      def hotwire_install?
        !(options[:skip_javascript] || options[:skip_hotwire])
      end

      def depends_on_system_test?
        !(options[:skip_system_test] || options[:skip_test] || options[:api])
      end

      def depend_on_bootsnap?
        !options[:skip_bootsnap] && !options[:dev] && !defined?(JRUBY_VERSION)
      end

      def run_bundle
        bundle_command("install", "BUNDLE_IGNORE_MESSAGES" => "1") if bundle_install?
      end

      def run_webpack
        return unless webpack_install?

        unless bundle_install?
          say <<~EXPLAIN
            Skipping `rails webpacker:install` because `bundle install` was skipped.
            To complete setup, you must run `bundle install` followed by `rails webpacker:install`.
          EXPLAIN
          return
        end

        rails_command "webpacker:install"
      end

      def run_importmap
        return unless importmap_install?

        unless bundle_install?
          say <<~EXPLAIN
            Skipping `rails importmap:install` because `bundle install` was skipped.
            To complete setup, you must run `bundle install` followed by `rails importmap:install`.
          EXPLAIN
          return
        end

        rails_command "importmap:install"
      end

      def run_hotwire
        return unless hotwire_install?

        unless bundle_install?
          say <<~EXPLAIN
            Skipping `rails turbo:install stimulus:install` because `bundle install` was skipped.
            To complete setup, you must run `bundle install` followed by `rails turbo:install stimulus:install`.
          EXPLAIN
          return
        end

        rails_command "turbo:install stimulus:install"
      end

      def generate_bundler_binstub
        if bundle_install?
          bundle_command("binstubs bundler")
        end
      end

      def empty_directory_with_keep_file(destination, config = {})
        empty_directory(destination, config)
        keep_file(destination)
      end

      def keep_file(destination)
        create_file("#{destination}/.keep") if keeps?
      end
    end
  end
end
