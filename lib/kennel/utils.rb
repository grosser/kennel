# frozen_string_literal: true
module Kennel
  module Utils
    COLORS = { red: 31, green: 32, yellow: 33, cyan: 36, magenta: 35, default: 0 }.freeze

    class << self
      def snake_case(string)
        string
          .gsub(/::/, "_") # Foo::Bar -> foo_bar
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2') # FOOBar -> foo_bar
          .gsub(/([a-z\d])([A-Z])/, '\1_\2') # fooBar -> foo_bar
          .tr("-", "_") # foo-bar -> foo_bar
          .downcase
      end

      # for child projects, not used internally
      def title_case(string)
        string.split(/[\s_]/).map(&:capitalize) * " "
      end

      # simplified version of https://apidock.com/rails/ActiveSupport/Inflector/parameterize
      def parameterize(string)
        string
          .downcase
          .gsub(/[^a-z0-9\-_]+/, "-") # remove unsupported
          .gsub(/-{2,}/, "-") # remove duplicates
          .gsub(/^-|-$/, "") # remove leading/trailing
      end

      def presence(value)
        value.nil? || value.empty? ? nil : value
      end

      def ask(question)
        Kennel.err.printf color(:red, "#{question} -  press 'y' to continue: ")
        begin
          STDIN.gets.chomp == "y"
        rescue Interrupt # do not show a backtrace if user decides to Ctrl+C here
          Kennel.err.print "\n"
          exit 1
        end
      end

      def color(color, text)
        "\e[#{COLORS.fetch(color)}m#{text}\e[0m"
      end

      def strip_shell_control(text)
        text.gsub(/\e\[\d+m(.*?)\e\[0m/, "\\1").gsub(/.#{Regexp.escape("\b")}/, "")
      end

      def capture_stdout
        old = Kennel.out
        Kennel.out = StringIO.new
        yield
        Kennel.out.string
      ensure
        Kennel.out = old
      end

      def capture_stderr
        old = Kennel.err
        Kennel.err = StringIO.new
        yield
        Kennel.err.string
      ensure
        Kennel.err = old
      end

      def path_to_url(path, subdomain: nil)
        subdomain ||= (ENV["DATADOG_SUBDOMAIN"] || "app")
        "https://#{subdomain}.datadoghq.com#{path}"
      end

      def parallel(items, max: 10)
        threads = [items.size, max].min
        work = items.each_with_index.to_a
        done = Array.new(items.size)
        workers = Array.new(threads).map do
          Thread.new do
            loop do
              item, i = work.pop
              break unless i
              done[i] =
                begin
                  yield item
                rescue Exception => e # rubocop:disable Lint/RescueException
                  work.clear
                  e
                end
            end
          end
        end
        workers.each(&:join)
        done.each { |d| raise d if d.is_a?(Exception) }
      end

      def natural_order(name)
        name.split(/(\d+)/).each_with_index.map { |x, i| i.odd? ? x.to_i : x }
      end

      def retry(*errors, times:)
        yield
      rescue *errors => e
        times -= 1
        raise if times < 0
        Kennel.err.puts "Error #{e}, #{times} retries left"
        retry
      end

      # https://stackoverflow.com/questions/20235206/ruby-get-all-keys-in-a-hash-including-sub-keys/53876255#53876255
      def all_keys(items)
        case items
        when Hash then items.keys + items.values.flat_map { |v| all_keys(v) }
        when Array then items.flat_map { |i| all_keys(i) }
        else []
        end
      end

      # TODO: use awesome-print or similar, but it has too many monkey-patches
      # https://github.com/amazing-print/amazing_print/issues/36
      def pretty_inspect(object)
        string = object.inspect.dup
        string.gsub!(/:([a-z_]+)=>/, "\\1: ")
        10.times do
          string.gsub!(/{(\S.*?\S)}/, "{ \\1 }") || break
        end
        string
      end
    end
  end
end
