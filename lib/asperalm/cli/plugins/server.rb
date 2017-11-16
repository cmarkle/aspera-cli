require 'asperalm/cli/main'
require 'asperalm/cli/basic_auth_plugin'
require 'asperalm/ascmd'
require 'asperalm/ssh'

module Asperalm
  module Cli
    module Plugins
      # implement basic remote access with FASP/SSH
      class Server < BasicAuthPlugin

        def initialize
        end

        alias super_declare_options declare_options

        def declare_options
          super_declare_options
          Main.tool.options.set_option(:ssh_keys,[])
          Main.tool.options.add_opt_simple(:ssh_keys,"PATH_ARRAY",Array,"PATH_ARRAY is @json:'[\"path1\",\"path2\"]'")
        end

        def action_list; [:nodeadmin,:userdata,:configurator,:download,:upload,:browse,:delete,:rename].push(*Asperalm::AsCmd.action_list);end

        # converts keys in hash table from symbol to string
        def convert_hash_sym_key(hash);h={};hash.each { |k,v| h[k.to_s]=v};return h;end

        def result_convert_hash_array(hash_array,fields)
          return {:data=>hash_array.map {|i| convert_hash_sym_key(i)},:type=>:hash_array,:fields=>fields.map {|f| f.to_s}}
        end

        def result_convert_key_val_list(key_val_list)
          return {:data=>convert_hash_sym_key(key_val_list),:type=>:key_val_list}
        end

        def execute_action
          server_uri=URI.parse(Main.tool.options.get_option(:url,:mandatory))
          Log.log.debug("URI : #{server_uri}, port=#{server_uri.port}, scheme:#{server_uri.scheme}")
          raise CliError,"Only ssh scheme is supported in url" if !server_uri.scheme.eql?("ssh")

          transfer_spec={
            "remote_host"=>server_uri.hostname,
            "remote_user"=>Main.tool.options.get_option(:username,:mandatory),
          }
          ssh_options={}
          if !server_uri.port.nil?
            ssh_options[:port]=server_uri.port
            transfer_spec["ssh_port"]=server_uri.port
          end
          cred_set=false
          password=Main.tool.options.get_option(:password,:optional)
          if !password.nil?
            ssh_options[:password]=password
            transfer_spec["password"]=password
            cred_set=true
          end
          ssh_keys=Main.tool.options.get_option(:ssh_keys,:optional)
          raise "internal error, expecting array" if !ssh_keys.is_a?(Array)
          if !ssh_keys.empty?
            ssh_options[:keys]=ssh_keys
            transfer_spec["EX_ssh_key_paths"]=ssh_keys
            cred_set=true
          end
          raise "either password or key must be provided" if !cred_set
          ssh_executor=Ssh.new(transfer_spec["remote_host"],transfer_spec["remote_user"],ssh_options)
          ascmd=Asperalm::AsCmd.new(ssh_executor)

          # get command and set aliases
          command=Main.tool.options.get_next_argument('command',action_list)
          command=:ls if command.eql?(:browse)
          command=:rm if command.eql?(:delete)
          command=:mv if command.eql?(:rename)
          begin
            case command
            when :nodeadmin,:userdata,:configurator
              realcmd="as"+command.to_s
              args = Main.tool.options.get_next_argument("#{realcmd} arguments",:multiple)
              # concatenate arguments, enclose in double quotes
              command = args.unshift(realcmd).map{|v|'"'+v+'"'}.join(" ")
              return {:data=>ssh_executor.exec_session(command),:type=>:status}
            when :upload
              filelist = Main.tool.options.get_next_argument("source list",:multiple)
              transfer_spec.merge!({
                'direction'=>'send',
                'paths'=>filelist.map { |f| {'source'=>f } }
              })
              return Main.tool.start_transfer(transfer_spec)
            when :download
              filelist = Main.tool.options.get_next_argument("source list",:multiple)
              transfer_spec.merge!({
                'direction'=>'receive',
                'paths'=>filelist.map { |f| {'source'=>f } }
              })
              return Main.tool.start_transfer(transfer_spec)
            when :mkdir; ascmd.mkdir(Main.tool.options.get_next_argument('path'));return Main.result_success
            when :mv; ascmd.mv(Main.tool.options.get_next_argument('src'),Main.tool.options.get_next_argument('dst'));return Main.result_success
            when :cp; ascmd.cp(Main.tool.options.get_next_argument('src'),Main.tool.options.get_next_argument('dst'));return Main.result_success
            when :rm; ascmd.rm(Main.tool.options.get_next_argument('path'));return Main.result_success
            when :ls; return result_convert_hash_array(ascmd.ls(Main.tool.options.get_next_argument('path')),[:name,:sgid,:suid,:size,:ctime,:mtime,:atime])
            when :info; return result_convert_key_val_list(ascmd.info())
            when :df; return {:data=>ascmd.df(),:type=>:key_val_list}
            when :du; return {:data=>ascmd.du(Main.tool.options.get_next_argument('path')),:type=>:key_val_list}
            when :md5sum; return {:data=>ascmd.md5sum(Main.tool.options.get_next_argument('path')),:type=>:key_val_list}
            end
          rescue Asperalm::AsCmd::Error => e
            raise CliBadArgument,e.extended_message
          end
        end
      end # Fasp
    end # Plugins
  end # Cli
end # Asperalm
