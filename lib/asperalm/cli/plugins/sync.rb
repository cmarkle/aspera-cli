require 'asperalm/cli/plugin'
require 'asperalm/sync'

module Asperalm
  module Cli
    module Plugins
      # list and download connect client versions, select FASP implementation
      class Sync < Plugin
        def declare_options
          self.options.add_opt_simple(:parameters,"extended value for session set definition")
        end

        def action_list; [ :start ];end

        def execute_action
          command=self.options.get_next_argument('command',action_list)
          case command
          when :start
            args,env=Asperalm::Sync.new(self.options.get_option(:parameters,:mandatory)).compute_args
            res=system(env,['async','async'],*args)
            Log.log.debug("result=#{res}")
            case res
            when true; return Plugin.result_success
            when false; return Plugin.result_status("failed: #{$?}")
            when nil; return Plugin.result_status("not started: #{$?}")
            else raise "internal error: unspecified case"
            end
          end # command
        end # execute_action
      end # Sync
    end # Plugins
  end # Cli
end # Asperalm
