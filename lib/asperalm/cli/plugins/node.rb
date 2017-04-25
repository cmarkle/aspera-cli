require 'asperalm/cli/basic_auth_plugin'

module Asperalm
  module Cli
    module Plugins
      class Node < BasicAuthPlugin
        attr_accessor :faspmanager
        alias super_set_options set_options
        def set_options
          super_set_options
          @option_parser.set_option(:persistency,File.join($PROGRAM_FOLDER,"persistency_cleanup.txt"))
          @option_parser.add_opt_simple(:persistency,"--persistency=FILEPATH","persistency file")
          @option_parser.add_opt_simple(:transfer_filter,"--transfer-filter=EXPRESSION","Ruby expression for filter at transfer level")
          @option_parser.add_opt_simple(:file_filter,"--file-filter=EXPRESSION","Ruby expression for filter at file level")
        end

        def self.format_browse(items)
          items.map {|i| i['permissions']=i['permissions'].map { |x| x['name'] }.join(','); i }
        end

        def self.result_translate(resp,type,default)
          resres={:fields=>[type,'result'],:values=>[]}
          JSON.parse(resp[:http].body)['paths'].each do |p|
            result=default
            if p.has_key?('error')
              Log.log.error("#{p['error']['user_message']} : #{p['path']}")
              result="ERROR: "+p['error']['user_message']
            end
            resres[:values].push({type=>p['path'],'result'=>result})
          end
          return resres
        end

        def self.delete_files(api_node,paths_to_delete)
          resp=api_node.call({:operation=>'POST',:subpath=>'files/delete',:json_params=>{:paths=>paths_to_delete.map {|i| {'path'=>i.start_with?('/') ? i : '/'+i}}}})
          #resp=api_node.create('files/delete',{:paths=>...})
          return result_translate(resp,'file','deleted')
        end

        def self.common_actions; [:browse, :mkdir, :delete, :upload, :download];end

        def self.execute_common(command,api_node,option_parser,faspmanager)
          case command
          when :browse
            thepath=option_parser.get_next_arg_value("path")
            send_result=api_node.call({:operation=>'POST',:subpath=>'files/browse',:json_params=>{ :path => thepath} } )
            #send_result={:data=>{'items'=>[{'file'=>"filename1","permissions"=>[{'name'=>'read'},{'name'=>'write'}]}]}}
            return nil if !send_result[:data].has_key?('items')
            return { :values => send_result[:data]['items'] , :textify => proc { |items| Node.format_browse(items)} }
          when :delete
            paths_to_delete = option_parser.get_remaining_arguments("file list")
            return delete_files(api_node,paths_to_delete)
          when :mkdir
            thepath=option_parser.get_next_arg_value("path")
            resp=api_node.call({:operation=>'POST',:subpath=>'files/create',:json_params=>{ "paths" => [{ "path" => thepath, "type" => "directory" } ] } } )
            return self.result_translate(resp,'folder','created')
            return { :format=>:ruby, :values => resp[:data] }# TODO
          when :upload
            filelist = option_parser.get_remaining_arguments("file list")
            Log.log.debug("file list=#{filelist}")
            raise CliBadArgument,"Missing source(s) and destination" if filelist.length < 2
            destination=filelist.pop
            send_result=api_node.call({:operation=>'POST',:subpath=>'files/upload_setup',:json_params=>{ :transfer_requests => [ { :transfer_request => { :paths => [ { :destination => destination } ] } } ] }})
            raise send_result[:data]['transfer_specs'][0]['error']['user_message'] if send_result[:data]['transfer_specs'][0].has_key?('error')
            raise "expecting one session exactly" if send_result[:data]['transfer_specs'].length != 1
            transfer_spec=send_result[:data]['transfer_specs'].first['transfer_spec']
            transfer_spec['paths']=filelist.map { |i| {'source'=>i} }
            faspmanager.transfer_with_spec(transfer_spec)
            return nil
          when :download
            filelist = option_parser.get_remaining_arguments("file list")
            Log.log.debug("file list=#{filelist}")
            raise CliBadArgument,"Missing source(s) and destination" if filelist.length < 2
            destination=filelist.pop
            send_result=api_node.call({:operation=>'POST',:subpath=>'files/download_setup',:json_params=>{ :transfer_requests => [ { :transfer_request => { :paths => filelist.map {|i| {:source=>i}; } } } ] }})
            raise send_result[:data]['transfer_specs'][0]['error']['user_message'] if send_result[:data]['transfer_specs'][0].has_key?('error')
            raise "expecting one session exactly" if send_result[:data]['transfer_specs'].length != 1
            transfer_spec=send_result[:data]['transfer_specs'].first['transfer_spec']
            transfer_spec['destination_root']=destination
            faspmanager.transfer_with_spec(transfer_spec)
            return nil
          end
        end

        def execute_action
          api_node=Rest.new(@option_parser.get_option_mandatory(:url),{:basic_auth=>{:user=>@option_parser.get_option_mandatory(:username), :password=>@option_parser.get_option_mandatory(:password)}})
          command=@option_parser.get_next_arg_from_list('command',self.class.common_actions.clone.concat([ :transfer, :info, :cleanup, :ak, :wf ]))
          case command
          when *self.class.common_actions; return self.class.execute_common(command,api_node,@option_parser,@faspmanager)
          when :transfer
            command=@option_parser.get_next_arg_from_list('command',[ :list, :cancel ])
            # ,:url_params=>{:active_only=>true}
            case command
            when :list
              resp=api_node.call({:operation=>'GET',:subpath=>'ops/transfers',:headers=>{'Accept'=>'application/json'},:url_params=>{'active_only'=>'true'}})
              return { :fields=>['id','status'], :values => resp[:data] } # TODO
            when :cancel
              trid=option_parser.get_next_arg_value("transfer id")
              resp=api_node.call({:operation=>'CANCEL',:subpath=>'ops/transfers/'+trid,:headers=>{'Accept'=>'application/json'}})
              return { :format=>:ruby, :values => resp[:data] } # TODO
            else
              raise "error"
            end
          when :info
            resp=api_node.call({:operation=>'GET',:subpath=>'info',:headers=>{'Accept'=>'application/json'}})
            return { :format=>:ruby, :values => resp[:data] }# TODO
            when :ak
              resp=api_node.call({:operation=>'GET',:subpath=>'access_keys',:headers=>{'Accept'=>'application/json'}})
              return {:fields=>['id','root_file_id','storage','license'],:values=>resp[:data]}
              #return { :values => resp[:data] }# TODO
            when :wf
              resp=api_node.call({:operation=>'GET',:subpath=>'/v3/watchfolders',:headers=>{'Accept'=>'application/json'}})
              #return {:fields=>['id','root_file_id','storage','license'],:values=>resp[:data]}
              return { :format=>:ruby, :values => resp[:data] }# TODO
          when :cleanup
            persistencyfile=@option_parser.get_option_mandatory(:persistency)
            transfer_filter=@option_parser.get_option_mandatory(:transfer_filter)
            file_filter=@option_parser.get_option_mandatory(:file_filter)
            Log.log.debug("transfer_filter: #{transfer_filter}")
            Log.log.debug("file_filter: #{file_filter}")
            # first time run ? or subsequent run ?
            iteration_token=nil
            if File.exist?(persistencyfile)
              iteration_token=File.read(persistencyfile)
            end
            params={:active_only=>false}
            params[:iteration_token]=iteration_token unless iteration_token.nil?
            resp=api_node.list('ops/transfers',params)
            transfers=resp[:data]
            if transfers.is_a?(Array) then
              # 3.7.2, released API
              iteration_token=URI.decode_www_form(URI.parse(resp[:http]['Link'].match(/<([^>]+)>/)[1]).query).to_h['iteration_token']
            else
              # 3.5.2, deprecated API
              iteration_token=transfers['iteration_token']
              transfers=transfers['transfers']
            end
            File.write(persistencyfile,iteration_token)
            # build list of files to delete: non zero files, downloads, for specified user
            paths_to_delete=[]
            transfers.each do |t|
              if eval(transfer_filter)
                t['files'].each do |f|
                  if eval(file_filter)
                    if !paths_to_delete.include?(f['path'])
                      paths_to_delete.push(f['path'])
                      Log.log.info("to delete: #{f['path']}")
                    end
                  end
                end
              end
            end
            # delete files, if any
            if paths_to_delete.length != 0
              Log.log.info("deletion")
              return self.delete_files(api_node,paths_to_delete)
            else
              Log.log.info("no new package")
            end
          end
          return nil
        end # execute_action
      end # Main
    end # Plugin
  end # Cli
end # Asperalm