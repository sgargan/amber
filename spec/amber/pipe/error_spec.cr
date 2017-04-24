require "../../spec_helper"

module Amber
  module Pipe
    describe Error do
      it "returns status code 404 when route not found" do
        router = Error.instance
        request = HTTP::Request.new("GET", "/")

        response = create_request_and_return_io(router, request)

        response.status_code.should eq 404
      end

      it "returns status code 500 for all other exceptions" do
        error = Error.instance
        request = HTTP::Request.new("GET", "/")
        error.next = ->(context : HTTP::Server::Context) { raise "Oops!" }

        response = create_request_and_return_io(error, request)

        response.status_code.should eq 500
      end
    end
  end
end