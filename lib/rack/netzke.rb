require 'netzke-core'

module Rack

  # Simple Rack middleware for netzke
  #
  # Simplest example:
  #
  #   use Rack::Netzke
  #
  # Now your application will forward all requests to
  # '/netzke/:action(.:format)' to netzke-core library
  #
  class Netzke
    ACTIONS = %w(direct dispatcher ext touch)
    REGEXP = %r{\A\/netzke\/([^\/]+?)(\.(.+)|\/)?\Z}

    def initialize(app)
      @app = app
    end

    def call(env)
      @logger = env['rack.logger']
      request = Rack::Request.new(env)
      action = extract_action(request)
      if ACTIONS.include?(action)
        set_session_data(env)
        send(action, request).to_a
      else
        @app.call(env)
      end
    end

    private

    def direct(request)
      response = Rack::Response.new
      begin
        raise "Missing body" unless request.body
        body_str = request.body.read
        request.body.rewind
        response.write invoke_endpoint(ActiveSupport::JSON.decode(body_str))
      rescue Exception => e
        log_error e.message
        log_error e.backtrace.join("\n")
        response.status = 500
      end
      response.to_a
    end

    def dispatcher(request)
      endpoint_dispatch(request.params['address'])
    end

    def ext(request)
      case request.env['netzke.format']
      when 'js'
        [
          200,
          {"Content-Type" => "text/javascript; charset=utf-8"},
          [::Netzke::Core::DynamicAssets.ext_js(form_authenticity_token(request.env))]
        ]
      when 'css'
        [
          200,
          {"Content-Type" => "text/css; charset=utf-8"},
          [::Netzke::Core::DynamicAssets.ext_css]
        ]
      else
        [406, {}, []]
      end
    end

    def touch(request)
      case request.env['netzke.format']
      when 'js'
        [
          200,
          {"Content-Type" => "text/javascript; charset=utf-8"},
          [::Netzke::Core::DynamicAssets.touch_js]
        ]
      when 'css'
        [
          200,
          {"Content-Type" => "text/css; charset=utf-8"},
          [::Netzke::Core::DynamicAssets.touch_css]
        ]
      else
        [406, {}, []]
      end
    end

    # @param [Hash] args the endpoint arguments
    # @option args [String] "endpoint_path"
    # @option args [String] "action"
    # @option args [Hash] "params"
    # @option args [String] "tid"
    # @option args [Hash] "_json" if this argument set, the request will be
    #   treated as batched.
    def invoke_endpoint(args = {})
      body = "["
      queries = args["_json"] ? args["_json"] : [args]
      queries.each_with_index do |query, ii|
        begin
          component_name, *sub_components = query["act"].split('__')
          action = query["method"].underscore
          components_in_session = ::Netzke::Core.session[:netzke_components]
          if components_in_session
            component_instance = ::Netzke::Base.instance_by_config(components_in_session[component_name.to_sym])
            endpoint = (sub_components + [action]).join("__")
            result = component_instance.invoke_endpoint(endpoint, *query["data"])
          else
            result = {:component_not_in_session => true}
          end
          body.concat({
            :type => "rpc",
            :tid => query["tid"],
            :action => component_name,
            :method => action,
            :result => (result.present? && result || {}).to_nifty_json.l
          }.to_json)
          body.concat(',') if ii < queries.size - 1
        rescue Exception => e
          log_error "!!! Netzke: Error invoking endpoint: #{query.inspect}"
          raise
        end
      end
      body.concat(']')
    end

    # Main dispatcher of old-style (Sencha Touch) HTTP requests. The URL
    # contains the name of the component, as well as the method of this
    # component to be called, according to the double underscore notation.
    # E.g.: some_grid__post_grid_data.
    def endpoint_dispatch(endpoint_path)
      component_name, *sub_components = endpoint_path.split('__')
      component_instance = ::Netzke::Base.instance_by_config(::Netzke::Core.session[:netzke_components][component_name.to_sym])
      [
        200,
        {"Content-Type" => "text/plain; charset=utf-8"},
        component_instance.invoke_endpoint(sub_components.join("__"), params).to_nifty_json
      ]
    end

    def extract_action(request)
      if matchdata = REGEXP.match(request.path_info)
        request.env['netzke.action'] = matchdata[1]
        request.env['netzke.format'] = matchdata[3]
        return request.env['netzke.action']
      end
    end

    def log_error(*args, &block)
      @logger.error(*args, &block) if @logger
    end

    def form_authenticity_token(env)
      if env['rack.session']
        env['rack.session']["_csrf_token"] ||= SecureRandom.base64(32)
      end
    end

    def set_session_data(env)
      if session = env['rack.session']
        ::Netzke::Core.session = session
        # set netzke_just_logged_in and netzke_just_logged_out states (may be used by Netzke components)
        if session[:_netzke_next_request_is_first_after_login]
          session[:netzke_just_logged_in] = true
          session[:_netzke_next_request_is_first_after_login] = false
        else
          session[:netzke_just_logged_in] = false
        end

        if session[:_netzke_next_request_is_first_after_logout]
          session[:netzke_just_logged_out] = true
          session[:_netzke_next_request_is_first_after_logout] = false
        else
          session[:netzke_just_logged_out] = false
        end
      end
    end
  end
end

