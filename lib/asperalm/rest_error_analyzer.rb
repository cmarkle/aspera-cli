require 'asperalm/fasp/installation'
require 'asperalm/log'
require 'asperalm/rest_call_error'
require 'json'
require 'singleton'

module Asperalm
  # builds a meaningful error message from known formats in Aspera products
  # TODO: probably too monolithic..
  class RestErrorAnalyzer
    include Singleton
    def initialize
      # list of handlers
      @error_handlers=[]
      # register generic handlers
      registerErrorTypes
    end

    # define error handler
    # @param name : type of exception handling (for logs)
    # @param block : processing of response: takes two parameters
    # * name
    # * context
    def add_handler(name,&block)
      @error_handlers.push({name: name, block: block})
    end

    # analyses rest call response and
    # raises a RestCallError exception if HTTP result code is not 2XX
    def raiseOnError(req,res)
      context={
        messages: [],
        request:  req,
        response: res[:http],
        data:     res[:data]
      }
      # multiple error messages can be found
      # analyze errors from provided handlers
      # note that there can be an error even if code is 2XX
      @error_handlers.each do |handler|
        begin
          Log.log.debug("test exception: #{handler[:name]}")
          handler[:block].call(handler[:name],context)
        rescue => e
          Log.log.error("ERROR in handler:\n#{e.message}\n#{e.backtrace}")
        end
      end
      unless context[:messages].empty?
        raise RestCallError.new(context[:request],context[:response],context[:messages].join("\n"))
      end
    end

    # used by handler to add an error description to list of errors
    # for logging and tracing : collect error descriptions (create file to activate)
    # @param context a Hash containing the result context, provided to handler
    # @param type a string describing type of exception, for logging purpose
    # @param msg one error message  to add to list
    def self.add_error(context,type,msg)
      context[:messages].push(msg)
      # log error for further analysis (file must exist to activate)
      exc_log_file=File.join(Fasp::Installation.instance.config_folder,'exceptions.log')
      if File.exist?(exc_log_file)
        File.open(exc_log_file,'a+') do |f|
          f.write("\n=#{type}=====\n#{context[:request].method} #{context[:request].path}\n#{context[:response].code}\n#{JSON.generate(context[:data])}\n#{context[:messages].join("\n")}")
        end
      end
    end

    private

    # handlers should probably be defined by plugins for modularity
    def registerErrorTypes
      # Faspex: both user_message and internal_message, and code 200
      # example: missing meta data on package creation
      add_simple_handler('Type 1: error:user_message','error','user_message',true)
      add_simple_handler('Type 2: error:description','error','description')
      add_simple_handler('Type 3: error:internal_message','error','internal_message')
      # AoC Automation
      add_simple_handler('AoC Automation','error')
      add_simple_handler('Type 5','error_description')
      add_simple_handler('Type 6','message')
      add_handler('Type 7') do |name,context|
        if context[:data].is_a?(Hash) and context[:data]['errors'].is_a?(Hash)
          context[:data]['errors'].each do |k,v|
            RestErrorAnalyzer.add_error(context,name,"#{k}: #{v}")
          end
        end
      end
      # call to upload_setup and download_setup of node api
      add_handler('T8:node: *_setup') do |type,context|
        if context[:data].is_a?(Hash)
          d_t_s=context[:data]['transfer_specs']
          if d_t_s.is_a?(Array)
            d_t_s.each do |res|
              #r_err=res['transfer_spec']['error']
              r_err=res['error']
              if r_err.is_a?(Hash)
                RestErrorAnalyzer.add_error(context,type,"#{r_err['code']}: #{r_err['reason']}: #{r_err['user_message']}")
              end
            end
          end
        end
      end
      add_simple_handler('T9:IBM cloud IAM','errorMessage')
      add_simple_handler('T10:faspex v4','user_message')
      add_handler('bss graphql') do |type,context|
        if context[:data].is_a?(Hash)
          d_t_s=context[:data]['errors']
          if d_t_s.is_a?(Array)
            d_t_s.each do |res|
              r_err=res['message']
              if r_err.is_a?(String)
                RestErrorAnalyzer.add_error(context,type,r_err)
              end
            end
          end
        end
      end
      add_handler('Type Generic') do |type,context|
        if !context[:response].code.start_with?('2')
          # add generic information
          RestErrorAnalyzer.add_error(context,type,"#{context[:request]['host']} #{context[:response].code} #{context[:response].message}")
        end
      end
    end # registerErrorTypes

    # simplest way to add a handler
    # check that key exists and is string under specified path (hash)
    # adds other keys as secondary information
    def add_simple_handler(name,*args)
      add_handler(name) do |type,context|
        # need to clone because we modify and same array is used subsequently
        path=args.clone
        Log.log.debug("path=#{path}")
        # if last in path is boolean it tells if the error is only with http error code or always
        always=[true, false].include?(path.last) ? path.pop : false
        if context[:data].is_a?(Hash) and (!context[:response].code.start_with?('2') or always)
          msg_key=path.pop
          # dig and find sub entry corresponding to path in deep hash
          error_struct=path.inject(context[:data]) { |subhash, key| subhash.respond_to?(:keys) ? subhash[key] : nil }
          Log.log.debug(">a:#{always}>p:#{path}> found s:#{error_struct}")
          if error_struct.is_a?(Hash) and error_struct[msg_key].is_a?(String)
            RestErrorAnalyzer.add_error(context,type,error_struct[msg_key])
            error_struct.each do |k,v|
              next if k.eql?(msg_key)
              RestErrorAnalyzer.add_error(context,"#{type}(sub)","#{k}: #{v}") if [String,Integer].include?(v.class)
            end
          end
        end
      end
    end # add_simple_handler

  end
end
