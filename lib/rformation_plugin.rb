module RFormation

  class Plugin < ActionView::TemplateHandler

    @@form_cache = {}

    include ActionView::TemplateHandlers::Compilable if defined?(ActionView::TemplateHandlers::Compilable)

    def compile(template)
      filename = template.filename
      form, id = RFormation::Plugin.create_form(filename)

      %{
        __lists_of_values__ = ::RFormation::Plugin::ListsOfValues.new(binding)
        __data__ = ::RFormation::Plugin::DataObjectContainer.new(binding)
        form = RFormation::Plugin.get_form(#{filename.inspect}, #{id.inspect})
        form.to_html(:data => __data__, :lists_of_values => __lists_of_values__)
      }
    end
    
    def self.register_form(filename, id, form)
      @@form_cache[[filename, id]] = form
    end
    
    def self.get_form(filename, id)
      @@form_cache[[filename, id]]
    end

    def self.create_form(filename)
      if ::File.exist? filename
        id = Digest::SHA1.file(filename).hexdigest
        unless form = get_form(filename.inspect, id)
          relative_filename = filename.sub(/\A#{Regexp.escape(RAILS_ROOT)}\//, "").sub(/\.html\.rfrm/, '')
          source = <<-RFRM_END
            ::RFormation::Form.new(:filename => #{filename.inspect}, :lists_of_values => proc { true }) do; object '$rformation$#{relative_filename}$#{id}' do; #{::File.read(filename)}
            end; end
          RFRM_END
          form = eval(source, binding, "FORM_DSL")
          RFormation::Plugin.register_form(filename, id, form)
        end
        [form, id]
      else
        nil
      end
    end

    def self.clean_params(params)
      form_data = {}
      params.keys.each do |key|
        if /\A\$rformation\$(.*)\$([a-fA-F0-9]+)\z/ === key.to_s
          filename = Rails.root.join($1 + ".html.rfrm").to_s
          if form = get_form(filename, $2)
            validate = true
          else
            form, id = create_form(filename)
            if form && id == $2
              validate = true
            else
              form_data[:form_errors] = {}
              if form
                form_data[:form_errors]["This form"] ||= "was changed on the server, please refresh this page and fill in the form again"
              else
                form_data[:form_errors]["This form"] ||= "does not exist"
              end
              validate = false
            end
          end
          if validate
            begin
              cleaned_data = form.validate_form({ key => params[key] })
              form_data.merge!(cleaned_data[key.to_s])
            rescue RFormation::ValidationError => e
              (form_data[:form_errors] ||= {}).merge!(e.errors)
              form_data.merge!(e.data[key.to_s])
            end
            params.delete(key)
          end
        end
      end
      params.merge!(form_data)
    end
    
    class DataObjectContainer
      
      def initialize(binding)
        @binding = binding
      end
      
      def respond_to?(m)
        true
      end
      
      def method_missing(m, *a)
        DataObject.new(@binding)
      end
      
    end
    
    class DataObject
      
      def initialize(binding)
        @binding = binding
      end
      
      def respond_to?(m)
        __vars.has_key?(m.to_s)
      end
      
      def method_missing(m, *a)
        __vars[m.to_s]
      end
      
      def __vars
        @vars ||= __local_vars.merge(__instance_vars)
      end
      
      def __local_vars
        @local_vars ||= eval("local_variables", @binding).inject({}) { |h, v| h[v.to_s] = eval(v, @binding) ; h }
      end
      
      def __instance_vars
        @instance_vars ||= eval("instance_variables", @binding).inject({}) { |h, v| h[v[/\A@(.*)/, 1]] = eval(v, @binding) ; h }
      end
      
    end
    
    class ListsOfValues
      
      def initialize(binding)
        @binding = binding
      end
      
    end

  end

end

if defined? ActionView::Template and ActionView::Template.respond_to? :register_template_handler
  ActionView::Template
else
  ActionView::Base
end.register_template_handler(:rfrm, RFormation::Plugin)

class ActionController::Base

  def perform_action_with_rformation(*a)
    RFormation::Plugin.clean_params(params)
    perform_action_without_rformation(*a)
  end
  
  alias_method_chain :perform_action, :rformation
  
end
