require 'aspera/fasp/manager'
require 'aspera/rest'
require 'aspera/open_application'
require 'securerandom'
require 'tty-spinner'

module Aspera
  module Fasp
    class Connect < Manager
      MAX_CONNECT_START_RETRY=3
      SLEEP_SEC_BETWEEN_RETRY=2
      private_constant :MAX_CONNECT_START_RETRY,:SLEEP_SEC_BETWEEN_RETRY
      def initialize
        super
        @connect_settings={
          'app_id' => SecureRandom.uuid
        }
        # TODO: start here and create monitor
      end

      def start_transfer(transfer_spec,options=nil)
        raise 'Using connect requires a graphical environment' if !OpenApplication.default_gui_mode.eql?(:graphical)
        trynumber=0
        begin
          connect_url=Installation.instance.connect_uri
          Log.log.debug("found: #{connect_url}")
          @connect_api=Rest.new({base_url: "#{connect_url}/v5/connect",headers: {'Origin'=>Rest.user_agent}}) # could use v6 also now
          cinfo=@connect_api.read('info/version')[:data]
        rescue => e # Errno::ECONNREFUSED
          raise StandardError,"Unable to start connect after #{trynumber} try" if trynumber >= MAX_CONNECT_START_RETRY
          Log.log.warn("connect is not started. Retry ##{trynumber}, err=#{e}")
          trynumber+=1
          if !OpenApplication.uri_graphical('fasp://initialize')
            OpenApplication.uri_graphical('https://downloads.asperasoft.com/connect2/')
            raise StandardError,'Connect is not installed'
          end
          sleep(SLEEP_SEC_BETWEEN_RETRY)
          retry
        end
        if transfer_spec['direction'] == 'send'
          Log.log.warn("Connect requires upload selection using GUI, ignoring #{transfer_spec['paths']}".red)
          transfer_spec.delete('paths')
          resdata=@connect_api.create('windows/select-open-file-dialog/',{'aspera_connect_settings'=>@connect_settings,'title'=>'Select Files','suggestedName'=>'','allowMultipleSelection'=>true,'allowedFileTypes'=>''})[:data]
          transfer_spec['paths']=resdata['dataTransfer']['files'].map { |i| {'source'=>i['name']}}
        end
        @request_id=SecureRandom.uuid
        # if there is a token, we ask connect client to use well known ssh private keys
        # instead of asking password
        transfer_spec['authentication']='token' if transfer_spec.has_key?('token')
        connect_settings=
        connect_transfer_args={
          'aspera_connect_settings'=>@connect_settings.merge({
          'request_id'               =>@request_id,
          'allow_dialogs'            =>true,
          }),
          'transfer_specs'         =>[{
          'transfer_spec'            =>transfer_spec,
          }]}
        # asynchronous anyway
        res=@connect_api.create('transfers/start',connect_transfer_args)[:data]
        @xfer_id=res['transfer_specs'].first['transfer_spec']['tags']['aspera']['xfer_id']
      end

      def wait_for_transfers_completion
        connect_activity_args={'aspera_connect_settings'=>@connect_settings}
        started=false
        spinner=nil
        loop do
          tr_info=@connect_api.create("transfers/info/#{@xfer_id}",connect_activity_args)[:data]
          if tr_info['transfer_info'].is_a?(Hash)
            trdata=tr_info['transfer_info']
            if trdata.nil?
              Log.log.warn("no session in Connect")
              break
            end
            # TODO: get session id
            case trdata['status']
            when 'completed'
              notify_end(@connect_settings['app_id'])
              break
            when 'initiating','queued'
              if spinner.nil?
                spinner = TTY::Spinner.new('[:spinner] :title', format: :classic)
                spinner.start
              end
              spinner.update(title: trdata['status'])
              spinner.spin
            when 'running'
              #puts "running: sessions:#{trdata['sessions'].length}, #{trdata['sessions'].map{|i| i['bytes_transferred']}.join(',')}"
              if !started and trdata['bytes_expected'] != 0
                notify_begin(@connect_settings['app_id'],trdata['bytes_expected'])
                started=true
              else
                notify_progress(@connect_settings['app_id'],trdata['bytes_written'])
              end
            else
              raise Fasp::Error.new("unknown status: #{trdata['status']}: #{trdata['error_desc']}")
            end
          end
          sleep 1
        end
        return [] #TODO
      end # wait
    end # Connect
  end
end
