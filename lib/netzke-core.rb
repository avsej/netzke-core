$LOAD_PATH << File.dirname(__FILE__)

require 'netzke/core'
require 'netzke/base'
require 'netzke/plugin'
require 'netzke/action_config'
require 'netzke/component_config'
require 'netzke/endpoint_response'

module Netzke
  autoload :Core, 'netzke/core'
  autoload :ExtComponent, 'netzke/ext_component'
end

# Rails specific
if defined? Rails
  require 'netzke/railz'

  ActiveSupport.on_load(:action_view) do
    include Netzke::Railz::ActionViewExt
  end
end
