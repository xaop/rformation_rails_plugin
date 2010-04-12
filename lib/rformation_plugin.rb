module RFormation

  class Plugin < ActionView::TemplateHandler

    @@form_cache = {}

    include ActionView::TemplateHandlers::Compilable if defined?(ActionView::TemplateHandlers::Compilable)

    def compile(template)
      filename = template.filename
      relative_filename = filename.sub(/\A#{Regexp.escape(RAILS_ROOT)}\//, "").sub(/\.html\.rfrm/, '')
      id = rand(2**64)
      %{
        __lists_of_values__ = ::RFormation::Plugin::ListsOfValues.new(binding)
        __data__ = ::RFormation::Plugin::DataObjectContainer.new(binding)
        form = eval(<<-RFRM_END, binding, "FORM_DSL")
          ::RFormation::Form.new(:filename => #{filename.inspect}, :lists_of_values => __lists_of_values__) do
            object '$rformation$#{relative_filename}$#{id}' do
              #{::File.read(filename).split(/\n/).map { |l| l.inspect[1..-2] }.join("\n")}
            end
          end
        RFRM_END
        RFormation::Plugin.register_form(#{filename.inspect}, #{id}, form)
        form.to_html(:data => __data__, :lists_of_values => __lists_of_values__)
      }
    end
    
    def self.register_form(filename, id, form)
      @@form_cache[[filename, id]] = form
    end
    
    def self.get_form(filename, id)
      @@form_cache[[filename, id]]
    end

    def self.clean_params(params)
      form_data = {}
      params.keys.each do |key|
        if /\A\$rformation\$(.*)\$(\d+)\z/ === key.to_s
          form = get_form(RAILS_ROOT + "/" + $1 + ".html.rfrm", $2.to_i)
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
