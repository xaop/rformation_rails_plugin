module RFormation

  class Plugin < ActionView::TemplateHandler

    @@form_cache = {}

    include ActionView::TemplateHandlers::Compilable if defined?(ActionView::TemplateHandlers::Compilable)

    def compile(template)
      %{
        lists_of_values = ::RFormation::Plugin::ListsOfValues.new(binding) ; data = ::RFormation::Plugin::DataObjectContainer.new(binding) ; form = ::RFormation::Plugin.get_form(#{template.filename.inspect}) ; form.to_html(:data => data, :lists_of_values => lists_of_values)
      }
    end

    def self.get_form(filename)
      cached_data = @@form_cache[filename]
      if !cached_data || cached_data[:mtime] < ::File.mtime(filename)
        relative_filename = filename.sub(/\A#{Regexp.escape(RAILS_ROOT)}\//, "")
        str = "object '$rformation$#{relative_filename}', :fix do ; #{::File.read(filename)} ; end"
        cached_data = @@form_cache[filename] = { :mtime => ::File.mtime(filename), :form => RFormation::Form.new(str, :filename => filename, :lists_of_values => proc { true }) }
      end
      cached_data[:form]
    end
    
    def self.clean_params(params)
      form_data = {}
      params.keys.each do |key|
        if /\A\$rformation\$(.*)/ === key.to_s
          form = get_form(RAILS_ROOT + "/" + $1)
          begin
            cleaned_data = form.validate_form({ key => params[key] })
            form_data.merge!(cleaned_data[key.to_s])
          rescue RFormation::ValidationError => e
            (form_data[:form_errors] ||= {}).merge!(e.errors)
          end
          params.delete(key)
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
