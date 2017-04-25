module Asperalm
  module Cli
    # base class for plugins modules
    class Plugin
      attr_accessor :option_parser
      def initialize(option_parser,defaults)
        @option_parser=option_parser
        @option_parser.set_defaults(defaults)
      end
    end # Plugin
  end # Cli
end # Asperalm