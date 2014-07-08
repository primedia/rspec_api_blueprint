require "rspec_api_blueprint/version"
require "rspec_api_blueprint/string_extensions"

module Rspec
  module API
    class Blueprint
      attr_accessor :authorization_header, :request, :response, :action, :example

      class << self

        def root_path
          if defined? Rails
            File.join(Rails.root, '/api_docs/')
          else
            File.join(File.expand_path('.'), '/api_docs/')
          end
        end

        def clean_api_docs_folder(folder_path = root_path)
          Dir.mkdir(folder_path) unless Dir.exists?(folder_path)

          Dir.glob(File.join(folder_path, '*')).each do |f|
            File.delete(f)
          end
        end

      end

      def initialize(example, request, response)
        @example, @request, @response = example, request, response
        @authorization_header = extract_auth_header(request)
      end

      def output_file(file_name = get_file_name)
        if defined? Rails
          File.join(Rails.root, "/api_docs/#{file_name}.txt")
        else
          File.join(File.expand_path('.'), "/api_docs/#{file_name}.txt")
          end
      end

      def example_groups
        # TODO: document that this is specific to the describe block structure

        group = example.metadata[:example_group]
        [group[:description_args], group[:example_group][:description_args]].flatten
      end

      def action
        String(example_groups[-2])
      end

      def get_file_name
        example_groups[-1].match(/(\w+)\s+Requests/i)[1].underscore
      end

      def header
        "# #{action}"
      end

      def content_type
        "+ Request #{request.content_type}"
      end

      def headers
        "+ Headers"
      end

      def authorization_header_block
        if authorization_header.present?
          [headers.indent(4), "Authorization: #{authorization_header}"].join
        end
      end

      def body_header
        "+ Body".indent(4) if authorization_header
      end

      def request_body_string(req_body)
        "#{JSON.pretty_generate(JSON.parse(req_body))}"
      end

      def response_header
        "+ Response #{response.status} #{response.content_type}"
      end

      def response_body
        if response.body.present? && response.content_type.to_s[/application\/json/]
          "#{JSON.pretty_generate(JSON.parse(response.body))}".indent(8)
        end
      end

      def request_body_block
        request_body = request.body.read
        if request_body.present? && request.content_type == 'application/json'
          output << body_header
          output << request_body(request_body).indent(authorization_header ? 12 : 8)
        end
      end

      def extract_auth_header(request)
        request.env ? request.env['Authorization'] : request.headers['Authorization']
      end

      def request_report
        if request.body.read.present? || authorization_header.present?
          [
            content_type,
            authorization_header,
            request_body_block,
          ]
        end
      end

      def presenter(*methods)
        output = methods.map do |m|
                   send(m.to_sym)
                 end

        output.flatten.map do |chunk|
          String(chunk)
        end.reject(&:empty?).join("\n\n").insert(-1, "\n\n")
      end
    end
  end
end

include Rspec::API

RSpec.configure do |config|
  config.before(:suite) do
    Blueprint.clean_api_docs_folder
  end

  config.after(:each, type: :request) do
    response ||= (@response || last_response)
    request ||= (@request || last_request)

    return unless response
    return if [401, 301, 403].include?(response.status)

    blueprint = Blueprint.new(example, request, response)

    output = blueprint.presenter(:header, :request_report, :response_header, :response_body)

    File.write(blueprint.output_file, output)
  end
end
