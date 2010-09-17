class QueryBuilder::Field
  
  attr_accessor :name, :human_name, :depth, :html_out_proc, :html_out_args, :query_conditions_proc, 
                :get_value_proc, :set_value_proc, :errors, :sub_fields, :default_field_wrapper_class
  
  def initialize(name = nil, human_name = nil, depth = 0, &block)
    @sub_fields = []
    @name = name
    @human_name = human_name
    @sub_fields = []
    @errors = []
    @depth = depth
    self.instance_eval(&block)
    unless self.html_out_proc
      self.html_out_proc = Proc.new{}
      self.html_out_args = []
    end
    # raise "no OUT proc for #{name}!" unless self.html_out_proc
  end
  
  #called by the DSL to define subfields
  def sub_field(named, human_name = nil, &block)
    human_name ||= named
    @sub_fields << QueryBuilder::Field.new(named, human_name, self.depth+1, &block)
  end
  
  def set_default_field_wrapper_class(to)
    self.default_field_wrapper_class = to
  end
  
  #called by the DSL to define how to display HTML
  def html_out(*args, &block)
    self.html_out_proc = block
    self.html_out_args = args
  end
  
  def get_value(&block)
    self.get_value_proc = block
  end
  def set_value(&block)
    self.set_value_proc = block
  end
  
  def valid_hash?(from_hash)
    traversal_from_hash(from_hash, {}) do |field, values_from_hash, sub_proc, options|
      unless field.is_a?(QueryBuilder::Field)
        RAILS_DEFAULT_LOGGER.warn("validation failure: #{from_hash.to_yaml} does not match with #{subfield_hash.to_yaml} "+
                    "because #{values_from_hash.to_yaml} does not match with #{field.to_yaml}")
        return false
      end
      sub_proc.call(options)
    end
    true
  end
  
  def load_object_from_hash(object, from_hash)
    # puts "loading object: #{object.inspect} from hash: " + from_hash.inspect    
    traversal_from_hash(from_hash, {}) do |field, values_from_hash, sub_proc, options|
      if field.set_value_proc
        result = field.set_value_proc.call([object] + values_from_hash)
      end
      sub_proc.call(options)
    end
    object
  end
  
  #Create hash that can be used to populate to_html in the same way that the hash from a form submission is used
  #by calling the get_value_proc on every field and aggregating the results appropriately
  def load_from_object(from_object)
    sub_field_loaded = {}
    @sub_fields.each do |field|
      result = field.load_from_object(from_object)
      sub_field_loaded[field.name] = result if result
    end
    if self.get_value_proc
      result = self.get_value_proc.call(from_object)
      if result
        if self.html_out_args.size > 1
          unless result.is_a?(Array)
            raise "result of 'get_value' on #{field}(#{field.name})"+
            " expected to be an array because there are multiple args"+
            " in html_out #{html_out_args}. But instead, got #{result}" 
          end
          self.html_out_args.each_with_index do |arg, index|
            sub_field_loaded[arg] = result[index] if result[index]
          end
        else          
          # puts "\n\nsub_field_loaded was" + sub_field_loaded.to_yaml
          if sub_field_loaded.keys.include?(result)
            sub_field_loaded = {result => sub_field_loaded[result]}
          end
          sub_field_loaded[self.html_out_args[0]] = result
          # puts "sub_field_loaded is now" + sub_field_loaded.to_yaml
        end
      end
    end
    unless sub_field_loaded.empty?
      to_return = {}
      self.html_out_args.each_with_index do |arg, index|
        to_return[arg] = sub_field_loaded.keys[index]
      end
      # puts "\n\nto_return " + to_return.to_yaml
      # puts "sub_field_loaded " + sub_field_loaded.to_yaml
      return to_return.merge(sub_field_loaded)
    else
      return false
    end
  end
  
  #call the stored html_out proc for this field (returing result of that call)
  def call_html_out_proc(form_helper, values)
    values ||= []
    call_with_array = [form_helper]
    unless values.empty?
      call_with_array += values
    else
      call_with_array += Array.new(html_out_args.size)
    end
    call_with_array << self.sub_fields
    html_out_proc.call(call_with_array)
  end
  
  #hash from: possible POST parameters => field
  def subfield_hash
    to_return = {}
    html_out_args.each do |val|
      to_return[val] = self
    end
    @sub_fields.each do |subfield|
      to_return[subfield.name] = subfield.subfield_hash
    end
    to_return
  end
  
  def fill_out_hash(hash)
    # puts "\n\n fill out hash " + hash.to_yaml
    # puts "should contain a key for at least one of " + html_out_args.inspect
    
    if @sub_fields.size == 0
      # puts "but there are no subfields"
      # puts "so create a subhash with html_out_args"
      html_out_args.each do |arg|
        hash[arg] = "" if hash[arg].nil?
      end
      return hash
    end
    
    key_subfield_name = html_out_args.first
    unless hash[key_subfield_name]
      # puts "key #{key_subfield_name.inspect} value #{@sub_fields.last.name.inspect}"
      hash[key_subfield_name] = @sub_fields.first.name
    end
    
    key_for_subhash = hash[key_subfield_name]
    
    # puts "now " + hash.to_yaml
    # puts "should contain a key for " + key_for_subhash.inspect
    
    hash[key_for_subhash] ||= {}  
    @sub_fields.each do |subfield|
      if subfield.name == hash[key_subfield_name]
        hash[key_for_subhash] = subfield.fill_out_hash(hash[key_for_subhash])
      end
    end
    
    # puts "\n\n result " + hash.to_yaml
    hash
  end
  
  def traversal_from_hash(from_hash, options = {})
    traversal = Proc.new do |hash_a, hash_b, opts1|
      a_vals = []
      b_vals = []
      sub_procs = [Proc.new{ "" }]
      hash_a.each do |key, value|
        if (value.is_a?(Hash) && hash_b[key].is_a?(Hash))
          sub_procs << Proc.new do |opts2|
            traversal.call(value, hash_b[key], opts2)
          end
        else
          unless hash_b[key].nil?
            a_vals << value
            b_vals << hash_b[key]
          end
        end
        # puts "a_vals #{a_vals.to_yaml}"
        # puts "b_vals #{b_vals}"
      end
      sub_proc = Proc.new do |opts3|
        sub_procs.collect do |sp|
          sp.call(opts3)
        end.join("")
      end
      a_vals.uniq.collect do |a_val|
        yield a_val, b_vals, sub_proc, opts1
      end
    end
    traversal.call(subfield_hash, from_hash, options)
  end
  
  #I feel like a LISP programmer
  def traversal_with_form_helper_and_css_id(from_hash, form_helper, container_css_id)
    traversal_from_hash(from_hash, {:form_helper => form_helper, :css_id => container_css_id}
    ) do |field, values_from_hash, sub_proc, options|
      sub_opts = {
          :form_helper => options[:form_helper], 
          :css_id => (field.name.nil?) ? options[:css_id] : "#{options[:css_id]}_#{field.name}"
      }
      unless field.name.nil?
        options[:form_helper].fields_for(field.name.to_s) do |the_real_f_sub|
          sub_opts[:form_helper] = the_real_f_sub
        end
      end
      
      yield field, values_from_hash, Proc.new{sub_proc.call(sub_opts)}, sub_opts[:form_helper], sub_opts[:css_id]
    end
  end
  
  #returns a hash of css_id => html output
  def to_hash_for_json(field_wrapper, form_helper, container_css_id)
    to_return = {}
    traversal_with_form_helper_and_css_id(subfield_hash, form_helper, container_css_id
    ) do |field, values_from_hash, sub_proc, f_sub, css_id|      
      to_return[css_id] = field_wrapper.wrap(css_id, field.depth, 
          field.call_html_out_proc(f_sub, []))
      sub_proc.call
    end
    to_return
  end
  
  def to_html(field_wrapper, form_helper, from_hash, container_css_id, collected_errors = nil)    
    traversal_with_form_helper_and_css_id(from_hash, form_helper, container_css_id) do |field, values_from_hash, sub_proc, f_sub, css_id|
      has_error = (collected_errors and collected_errors.error_on?(field))
      field_wrapper.wrap(css_id, field.depth, field.call_html_out_proc(f_sub, values_from_hash).html_safe + sub_proc.call.html_safe, has_error)
    end.join("")
  end
  
  def query_conditions(&block)
    self.query_conditions_proc = block
  end
  
  def load_query_conditions_and_errors(from_hash, error_collector, default_proc = nil)
    conditions_to_return = []
    traversal_from_hash(from_hash) do |field, values_from_hash, sub_proc, options|
      begin
        if proc_to_call = field.query_conditions_proc || default_proc
          if field.html_out_args.size > 1
            conditions_to_return << proc_to_call.call(values_from_hash)
          else
            conditions_to_return << proc_to_call.call(values_from_hash[0])          
          end
        end
      rescue => e
        error_collector.add_error(field, e)
      end
      sub_proc.call(options)
    end
    conditions_to_return
  end

  #THis method for DEBUG only
  def to_yaml(arg = {})
    "subfield: #{name} #{object_id}".to_yaml(arg)
  end
      
end