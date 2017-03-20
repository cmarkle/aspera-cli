require 'asperalm/rest'
require 'asperalm/colors'
require 'asperalm/fasp_manager'
require 'asperalm/log'
require 'formatador'
require 'pp'
require 'xmlsimple'
require 'optparse'

module Asperalm
  module Cli
    # base class for plugins modules
    class Plugin < OptionParser
      @@TOOL_HOME=File.join(Dir.home,'.aspera/ascli')
      def self.home
        return @@TOOL_HOME
      end

      # parse an option value, special behavior for file:, env:, val:
      def self.get_extended_value(pname,value)
        if m=value.match(/^@file:(.*)/) then
          value=m[1]
          if m=value.match(/^~\/(.*)/) then
            value=m[1]
            value=File.join(Dir.home,value)
          end
          raise OptionParser::InvalidArgument,"cannot open file \"#{value}\" for #{pname}" if ! File.exist?(value)
          value=File.read(value)
        elsif m=value.match(/^@env:(.*)/) then
          value=m[1]
          value=ENV[value]
        elsif m=value.match(/^@val:(.*)/) then
          value=m[1]
        end
        value
      end

      def self.get_next_arg_from_list(argv,descr,action_list)
        if argv.empty? then
          raise OptionParser::InvalidArgument,"missing action, one of: #{action_list.map {|x| x.to_s}.join(', ')}"
        end
        action=argv.shift.to_sym
        if !action_list.include?(action) then
          raise OptionParser::InvalidArgument,"unexpected value for #{descr}: #{action}, one of: #{action_list.map {|x| x.to_s}.join(', ')}"
        end
        return action
      end

      def self.get_next_arg_value(argv,descr)
        if argv.empty? then
          raise OptionParser::InvalidArgument,"expecting value: #{descr}"
        end
        return get_extended_value(descr,argv.shift)
      end

      def self.get_remaining_arguments(argv,descr)
        filelist = argv.pop(argv.length)
        Log.log.debug("#{descr}=#{filelist}")
        if filelist.empty? then
          raise OptionParser::InvalidArgument,"missing #{descr}"
        end
        return filelist
      end

      def get_formats; [:ruby,:text]; end

      def exit_with_usage
        STDERR.puts self
        Process.exit 1
      end

      def set_obj_val(pname,value)
        value=self.class.get_extended_value(pname,value)
        method='set_'+pname.to_s
        if self.respond_to?(method) then
          self.send(method,value)
        else
          self.instance_variable_set('@'+pname.to_s,value)
        end
        Log.log.info("set #{pname} to #{value}")
      end

      def set_defaults(values)
        return if values.nil?
        params=self.send('opt_names')
        Log.log.info("defaults=#{values}")
        Log.log.info("params=#{params}")
        params.each { |pname|
          set_obj_val(pname,values[pname]) if values.has_key?(pname)
        }
      end

      def add_opt_list(pname,help,*args)
        Log.log.info("add_opt_list #{pname}->#{args}")
        values=self.send('get_'+pname.to_s+'s')
        method='get_'+pname.to_s
        if self.respond_to?(method) then
          value=self.send(method)
        else
          value=self.instance_variable_get('@'+pname.to_s)
        end
        self.on( *args , values, "#{help}. Values=(#{values.join(',')}), current=#{value}") do |v|
          theval = v.to_sym
          if values.include?(theval) then
            set_obj_val(pname,theval)
          else
            raise OptionParser::InvalidArgument,"unknown value for #{pname}: #{v}"
          end
        end
      end

      def add_opt_simple(pname,*args)
        Log.log.info("add_opt_simple #{pname}->#{args}")
        self.on(*args) { |v| set_obj_val(pname,v) }
      end

      def get_option_optional(pname)
        return self.instance_variable_get('@'+pname.to_s)
      end

      def set_option(pname,value)
        return self.instance_variable_set('@'+pname.to_s,value)
      end

      def get_option_mandatory(pname)
        value=get_option_optional(pname)
        if value.nil? then
          raise OptionParser::InvalidArgument,"Missing option in context: #{pname}"
        end
        return value
      end
      @@GEM_PLUGINS_FOLDER='asperalm/cli/plugins'
      @@CLI_MODULE=Module.nesting[1].to_s
      @@PLUGINS_MODULE=@@CLI_MODULE+"::Plugins"

      def self.get_plugin_list
        gem_root=File.expand_path(@@CLI_MODULE.to_s.gsub('::','/').gsub(%r([^/]+),'..'), File.dirname(__FILE__))
        plugin_folder=File.join(gem_root,@@GEM_PLUGINS_FOLDER)
        return Dir.entries(plugin_folder).select { |i| i.end_with?('.rb')}.map { |i| i.gsub(/\.rb$/,'').to_sym}
      end

      def self.new_plugin(app_name)
        require File.join(@@GEM_PLUGINS_FOLDER,app_name.to_s)
        # TODO: check that ancestor is Plugin
        application=Object::const_get(@@PLUGINS_MODULE+'::'+app_name.to_s.capitalize).new
        if application.respond_to?(:faspmanager=) then
          # create the FASP manager for transfers
          faspmanager=FaspManager.new
          faspmanager.set_listener(FaspListenerLogger.new)
          application.faspmanager=faspmanager
        end
        return application
      end

      def command_list
        throw "virtual method"
      end

      def set_options
        throw "virtual method"
      end

      def dojob(command,argv)
        throw "virtual method"
      end

      def command_name
        return self.class.to_s.downcase.gsub(%r{.*::},'')
      end

      def parse_options!(argv)
        options=[]
        while !argv.empty? and argv.first =~ /^-/
          options.push argv.shift
        end
        Log.log.info("split -#{options}-#{argv}-")
        self.parse!(options)
      end

      def go(argv,defaults)
        self.set_defaults(defaults)
        self.banner = "NAME\n\t#{$PROGRAM_NAME} -- a command line tool for Aspera Applications\n\n"
        self.separator "SYNOPSIS"
        self.separator "\t#{$PROGRAM_NAME} #{command_name} [OPTIONS] COMMAND [ARGS]..."
        self.separator ""
        self.separator "COMMANDS"
        self.separator "\tSupported commands: #{command_list.map {|x| x.to_s}.join(', ')}"
        self.separator ""
        self.separator "OPTIONS"
        self.on_tail("-h", "--help", "Show this message") { self.exit_with_usage }
        @format=:text
        self.add_opt_list(:format,"output format",'--format=TYPE')
        set_options
        parse_options!(argv)
        command=self.class.get_next_arg_from_list(argv,'command',command_list)
        results=dojob(command,argv)
        if !argv.empty?
          raise OptionParser::InvalidArgument,"unprocessed values: #{argv}"
        end
        if results.is_a?(Hash) and results.has_key?(:values) and results.has_key?(:fields) then
          case @format
          when :ruby
            puts PP.pp(results[:values],'')
          when :text
            #results[:values].each { |i| i.select! { |k| results[:fields].include?(k) } }
            Formatador.display_table(results[:values],results[:fields])
          end
        else
          puts ">result>#{PP.pp(results,'')}"
        end
      end
    end
  end
end
