# frozen_string_literal: true
module Kennel
  module ValidatePlan
    class MonitorValidator
      COSMETIC_FIELDS = ["name", "message", "tags"].freeze

      def initialize(item)
        @item = item
      end

      def validate(api)
        data = @item.expected.as_json

        # ignore unresolved ids from yet to be created monitors
        return nil if ["composite", "slo alert"].include?(data[:type]) && data[:query].include?("%")

        api.send(:request, :post, "/api/v1/monitor/validate", body: data)
        nil
      rescue StandardError => e
        "#{Kennel::Console.color(:yellow, "#{@item.api_resource} #{@item.tracking_id}:")}\n#{e.message}"
      end
    end

    class DashboardValidator
      COSMETIC_FIELDS = ["title", "description", "tags"].freeze

      def initialize(item)
        @item = item
      end

      # datadog does not offer a validation api for dashboards,
      # so we insert an invalid widget at the end and see if that is the invalid widget it complains about
      # this will break if they ever start from the back or return errors for everything that is invalid
      #
      # we do not need to worry about unresolved ids because:
      # - alert_graph widgets allows kennel style ids
      # - slo widgets allow kennel style ids
      # - uptime widgets allow kennel style ids
      def validate(api)
        json = @item.expected.as_json
        json = Marshal.load(Marshal.dump(json))

        # add a semi-valid (does not fail immediately on missing definition) widget still blocks the request
        placeholder = "invalid_metric_do_not_update"
        json.fetch(:widgets) << {
          definition: {
            type: "timeseries", requests: [{
              response_format: "timeseries",
              queries: [{ data_source: "metrics", name: "restarts", query: placeholder }]
            }]
          },
          layout: { x: 0, y: 0, height: 0, width: 0 } # needed for `layout_type: free` and valid for all
        }

        begin
          if @item.class::TYPE == :update
            api.update("dashboard", @item.actual.fetch(:id), json)
          else
            api.create("dashboard", json)
          end
          raise "Dashboard validation should have failed, live dashboard was update/created by accident"
        rescue StandardError => e
          # parse the JSON in the error message and see if there is anything except our error
          raise "Unreadable error format: #{e.message}" unless (json = e.message[/^\{"errors":.*}$/m])
          data =
            begin
              JSON.parse(json)
            rescue JSON::ParserError
              raise "Unreadable error format: #{json}"
            end
          raise "Unreadable error format: #{data}" unless (errors = data["errors"]) # uncovered
          return if errors.size == 1 && errors.all? { |m| m.include?("unable to parse #{placeholder}") }
          "#{@item.tracking_id}: #{e.message}"
        end
      end
    end

    VALIDATORS = {
      "monitor" => MonitorValidator,
      "dashboard" => DashboardValidator
    }.freeze

    def self.validate(plan)
      changes = (plan.creates + plan.updates)

      validators = changes.filter_map do |item|
        next unless (validator = VALIDATORS[item.api_resource]&.new(item))

        if item.class::TYPE == :update
          # ignore if nothing can break
          modified_fields = item.diff.map { |_, f, *| f }
          next nil if modified_fields.all? { |f| validator.class::COSMETIC_FIELDS.include?(f) }
        end

        validator
      end

      api = Kennel::Api.new
      errors = validators.filter_map { |v| v.validate(api) }
      return if errors.empty?

      abort "#{Kennel::Console.color(:red, "#{errors.size} validation(s) failed:")}\n#{errors.join("\n")}"
    end
  end
end

namespace :kennel do
  desc "Validate planned changes against the Datadog API [PROJECT=]"
  task "validate_plan" => "kennel:environment" do
    kennel = Kennel::Tasks.kennel
    kennel.preload
    Kennel::ValidatePlan.validate(kennel.plan)
  end
end
