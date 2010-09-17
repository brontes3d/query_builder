class QueryBuilder
  
  attr_accessor :field_wrapper, :query_conditions, :collected_errors
  
  def initialize(root_field, field_wrapper = nil)
    @root_field = root_field
    if field_wrapper
      @field_wrapper = field_wrapper
    elsif field_wrapper_class = @root_field.default_field_wrapper_class
      @field_wrapper = field_wrapper_class.new
    else
      @field_wrapper = QueryBuilder::FieldWrapper.new
    end    
    @collected_errors = {}    
    @query_conditions = []
    @params = {}
  end
  
  def each_field_in_hash(hash)
    index = 0;
    hash.keys.each do |key|
      if(key.to_s.index("field") == 0)
        yield key, hash[key], index
        index += 1;
      end
    end
  end
  
  def load_params(params)
    @params = {}
    default_proc = Proc.new do |value|
      raise "cannot be blank" if value.blank?
    end
    each_field_in_hash(params) do |key, value, index|
      @params[key] = value.clone
      @collected_errors[key] = QueryBuilder::FieldErrors.new
      @query_conditions += @root_field.load_query_conditions_and_errors(@params[key], @collected_errors[key], default_proc)
    end
    self
  end
  
  def load_from_objects(array_of_objects)
    hash_result = {}
    array_of_objects.each_with_index do |object, index|
      hash_result["field_#{index}"] = @root_field.load_from_object(object)
    end
    hash_result
  end
  
  def load_objects_from_hash(array_of_objects, from_hash)
    validate_hash!(from_hash)
    each_field_in_hash(from_hash) do |key, value, index|
      array_of_objects[index] = @root_field.load_object_from_hash(array_of_objects[index], value)
    end
    array_of_objects
  end
    
  
  def validate_hash!(hash)
    each_field_in_hash(hash) do |key, value, index|
      unless @root_field.valid_hash?(value)
        raise ArgumentError, "bad hash for #{key}, can't load from that"
      end
    end
  end
  
  def generate_html_and_javascript(form_helper, options={})
    if(options[:default_hash] && @params.empty?)
      @params = options[:default_hash]
    end
    if(options[:remove_link] == false)
      @field_wrapper.show_remove_link = false
    end
    string_prefix = form_helper.object_name.to_s.gsub(/[\[\]]+/, "_")
    to_return = "<div id='#{string_prefix}query_builder_placeholder' style='display:none;'></div>"
    highest_value = 0
    @params.keys.sort do |a,b|
      a_val = a[/[0-9]+/].to_i
      b_val = b[/[0-9]+/].to_i
      a_val <=> b_val
    end.each do |key|
      highest_value = key[/[0-9]+/].to_i;
      to_return += to_html(form_helper, key, @params[key])
    end
    to_return + %Q{
      <script>  		  
		    create_query_builder('#{string_prefix}', #{highest_value}, #{to_json(form_helper)});		    
      </script>
    }
  end
  
  def javascript_for_add_button(form_helper)
    "query_builder_add_field('#{form_helper.object_name.to_s.gsub(/[\[\]]+/, "_")}');return false;"
  end
  
  def to_html(form_helper, name_prefix, from_hash)
    full_prefix = form_helper.object_name.to_s.gsub(/[\[\]]+/, "_") + name_prefix
    form_helper.fields_for(name_prefix) do |f_sub|
      @root_field.to_html(field_wrapper, f_sub, @root_field.fill_out_hash(from_hash), full_prefix, @collected_errors[name_prefix])
    end
  end
  
  def to_json(form_helper)
    full_prefix = form_helper.object_name.to_s.gsub(/[\[\]]+/, "_") + 'field_index'
    form_helper.fields_for('field_index') do |f_sub|
      @root_field.to_hash_for_json(field_wrapper, f_sub, full_prefix).to_json
    end
  end
  
  #TODO: alter test to reflect change here to allow query_conditions to be a hash with :conditions => 
  def extract_query_conditions(join_string = "AND")
    Rails.logger.debug { "extract_query_conditions ..." }
    
    return @extracted_query_conditions if @extracted_query_conditions
    conditions_string = ""
    condition_values = []
    query_conditions.each do |condition|
      Rails.logger.debug { "condition = #{condition.inspect}" }
      
      unless condition.nil? || condition.empty?
        Rails.logger.debug { "loading from condition: #{condition.inspect}" }
        conditions_string += " #{join_string} " unless conditions_string.blank?
        if condition.is_a?(Hash)
          condition = condition[:conditions]
        end
        conditions_string += ("(" + condition.shift + ")")
        condition_values += condition
      end
    end
    @extracted_query_conditions = ([conditions_string] + condition_values)
  end
  
  #TODO: alter test to reflect new method
  def extract_includes
    return @extract_includes if @extract_includes
    @extract_includes = []
    query_conditions.each do |condition|
      unless condition.nil? || condition.empty?
        if(condition.is_a?(Hash) && condition[:include])
          @extract_includes << condition[:include]
        end
      end
    end
    @extract_includes.uniq!
    @extract_includes
  end
  
end