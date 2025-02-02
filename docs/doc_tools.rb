# get transfer spec parameter description
$LOAD_PATH.unshift(ENV["INCL_DIR_GEM"])
require 'aspera/fasp/parameters'

# check that required env vars exist, and files
%w{EXENAME GEMSPEC INCL_USAGE INCL_COMMANDS INCL_ASESSION INCL_DIR_GEM}.each do |e|
  raise "missing env var #{e}" unless ENV.has_key?(e)
  raise "missing file #{ENV[e]}" unless File.exist?(ENV[e]) or !e.start_with?('INCL_')
end

# set values used in ERB
# just command name
def cmd;ENV['EXENAME'];end

# used in text with formatting of command
def tool;'`'+cmd+'`';end

# prefix for env vars
def evp;cmd.upcase+'_';end

# just the name for "option preset"
def opprst;'option preset';end

# name with link
def prst;'['+opprst+'](#lprt)';end

# name with link (plural)
def prsts;'['+opprst+'s](#lprt)';end

# in title
def prstt;opprst.capitalize;end

def gemspec;Gem::Specification::load(ENV['GEMSPEC']) or raise "error loading #{ENV["GEMSPEC"]}";end

def geminstadd;gemspec.version.to_s.match(/\.[^0-9]/)?' --pre':'';end

# transfer spec description generation
def spec_table
  r='<table><tr><th>Field</th><th>Type</th>'
  Aspera::Fasp::Parameters::SUPPORTED_AGENTS_SHORT.each do |c|
    r << '<th>'<<c.to_s.upcase<<'</th>'
  end
  r << '<th>Description</th></tr>'
  Aspera::Fasp::Parameters.man_table.each do |p|
    p[:description] << (p[:description].empty? ? '' : "\n") << "(" << p[:cli] << ")" unless p[:cli].to_s.empty?
    p.delete(:cli)
    p.keys.each{|c|p[c]='&nbsp;' if p[c].to_s.empty?}
    p[:description].gsub!("\n",'<br/>')
    p[:type].gsub!(',','<br/>')
    r << '<tr><td>'<<p[:name]<<'</td><td>'<<p[:type]<<'</td>'
    Aspera::Fasp::Parameters::SUPPORTED_AGENTS_SHORT.each do |c|
      r << '<td>'<<p[c]<<'</td>'
    end
    r << '<td>'<<p[:description]<<'</td></tr>'
  end
  r << '</table>'
  return r
end
