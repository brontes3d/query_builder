require 'test/unit'
#require this plugin
require "#{File.dirname(__FILE__)}/../init"

require 'rubygems'
require 'active_support'

class MockFormBuilder
  def initialize(name, parent = nil)
    @name = name
    @parent = parent
  end
  def fields_for(name)
    yield MockFormBuilder.new(name, self)
  end
  def to_s
    "(" + (@parent ? @parent.to_s + @name : @name) + ")"
  end
end

class MockObjectLikeFieldHashes
  attr_accessor :status, :last_login_after, :created_at_after, :last_login_between_after, 
                :last_login_between_before, :date_type, :created_at_between_after, :created_at_between_before
end

class SpecialTestWrapper
  
  def wrap(css_id, depth, to_wrap, in_error = false)
    if in_error
      "[ ERROR ]"
    else
      "[ " + css_id + to_wrap + " ]"
    end
  end
  
end

RAILS_DEFAULT_LOGGER = Logger.new(nil) unless defined?(RAILS_DEFAULT_LOGGER)

class QueryBuilderTest < Test::Unit::TestCase
  
  def setup
    @@string_we_dont_like_to_see = "we don't want to see this value"
    
    @posted_hash = {
      'reporting' => {
          'field_1' => {
            'date' => {
              'last_login' => {'after' => {'after' => 'after_value'},
                              'last_login_select' => 'after'},
              'date_select' => 'last_login'
             },
             'report' => 'date'             
          },
          'field_2' => {
            'date' => {
              'last_login' => {'between' => {'after' => 'between_after_value', 'before' => 'between_before_value'},
                              'last_login_select' => 'between'},
              'date_select' => 'last_login'
             },
             'report' => 'date'
            },
      }
    }
    @field_defaults_hash = {
      'date' => {
        'date_select' => 'last_login'
       },
       'report' => 'date'       
    }
    @raises_errors_hash = {
      'date' => {
        'last_login' => {'after' => {'after' => @@string_we_dont_like_to_see},
                        'last_login_select' => 'after'},
        'date_select' => 'last_login'
       },
       'report' => 'date'
    }
        
    @field_1_hash = @posted_hash['reporting']['field_1']
    @mock_object_like_field_1 = MockObjectLikeFieldHashes.new
    @mock_object_like_field_1.date_type = 'last_login'
    @mock_object_like_field_1.created_at_after = @@string_we_dont_like_to_see
    @mock_object_like_field_1.last_login_after = "after_value"

    @field_2_hash = @posted_hash['reporting']['field_2']
    @mock_object_like_field_2 = MockObjectLikeFieldHashes.new
    @mock_object_like_field_2.date_type = 'last_login'
    @mock_object_like_field_2.created_at_after = @@string_we_dont_like_to_see
    @mock_object_like_field_2.created_at_between_after = @@string_we_dont_like_to_see
    @mock_object_like_field_2.created_at_between_before = @@string_we_dont_like_to_see
    @mock_object_like_field_2.last_login_between_after = 'between_after_value'
    @mock_object_like_field_2.last_login_between_before = 'between_before_value'
    
    @field_definition = root_field_definition
  end
  
  def test_valid_hash
    assert @field_definition.valid_hash?(@field_defaults_hash)
    assert @field_definition.valid_hash?(@field_1_hash)
    assert @field_definition.valid_hash?(@field_2_hash)
    assert @field_definition.valid_hash?({'report' => 'date'})
    assert !@field_definition.valid_hash?({'date' => "this should be a hash not a value"})
    assert !@field_definition.valid_hash?({'date' => "this should be a hash not a value", 'report' => 'date'})
  end
  
  def test_subfield_hash
    #we are testing the result of this call
    subfield_hash = @field_definition.subfield_hash

    #Test that some specific things exist in the subfield_hash based on what's hard-coded in root_field_definition
    assert(subfield_hash['date'].is_a?(Hash))
    assert(subfield_hash['date']['last_login'].is_a?(Hash))
    assert(subfield_hash['date']['last_login']['within_last'].is_a?(Hash))
    assert(subfield_hash['date']['last_login']['within_last']['value'].is_a?(QueryBuilder::Field))
    assert(subfield_hash['date'].is_a?(Hash))
    assert(subfield_hash['date']['created_at'].is_a?(Hash))
    assert(subfield_hash['date']['created_at']['after'].is_a?(Hash))
    assert(subfield_hash['date']['created_at']['after']['after'].is_a?(QueryBuilder::Field))    
    
    #Constructing an array containing every subfield by using the sub_fields method recursively
    all_subfields = []
    subfield_traversal = Proc.new do |field|
      all_subfields << field
      field.sub_fields.each do |f|
        subfield_traversal.call(f)
      end
    end
    subfield_traversal.call(@field_definition)
    # puts "\n\n all_subfields \n\n " + all_subfields.to_yaml
    # puts subfield_hash.to_yaml
    
    #Contructing an array of every subfield found in the subfield_hash
    traversal_found_subfields = []
    hash_traversal = Proc.new do |key, val|
      if val.is_a?(QueryBuilder::Field)
        traversal_found_subfields << val
        assert(val.html_out_args.include?(key), "'#{key}' should be among #{val.html_out_args}")
      elsif val.is_a?(Hash)
        val.each{ |k, v| hash_traversal.call(k,v) }
        #test the keys too?
      else
        assert(false, "subfield_hash should contain only hashes of subfields, #{val} does not fit in")
      end
    end
    hash_traversal.call("", subfield_hash)
    
    #Testing that the 2 arrays are contain the same thing (traversal_found_subfields may contain duplicates, and that's ok)
    all_subfields.uniq.each do |field|
      assert(traversal_found_subfields.include?(field), "subfield_hash should contain #{field.inspect}")
    end
    traversal_found_subfields.uniq.each do |field|
      assert(all_subfields.include?(field), "#{field.inspect} is in subfield_hash but was not found in collection of subfields")
    end
  end
  
  #test to_html (with and without a values hash)
  def test_to_html
    assert_equal("", @field_definition.to_html(SpecialTestWrapper.new, MockFormBuilder.new('field_1'), {}, 'reporting_field_1'),
      "to_html for an empty hash should be empty string")

    field_1_html = @field_definition.to_html(SpecialTestWrapper.new, MockFormBuilder.new('field_1'), @field_1_hash, 'reporting_field_1')
    assert_equal(
      %Q{ [ reporting_field_1(field_1) => 
            date[ reporting_field_1_date((field_1)date) => 
              last_login[ reporting_field_1_date_last_login(((field_1)date)last_login) => 
                after[ reporting_field_1_date_last_login_after((((field_1)date)last_login)after) => 
                  after_value ] ] ] ] }.gsub(" ",""), 
                  field_1_html.gsub(" ",""))
    
    field_2_html = @field_definition.to_html(SpecialTestWrapper.new, MockFormBuilder.new('field_2'), @field_2_hash, 'reporting_field_2')
    assert_equal(
      %Q{ [ reporting_field_2(field_2) => 
          date[ reporting_field_2_date((field_2)date) => 
            last_login[ reporting_field_2_date_last_login(((field_2)date)last_login) => 
              between[ reporting_field_2_date_last_login_between((((field_2)date)last_login)between) => 
                between_after_value,between_before_value ] ] ] ] }.gsub(" ",""), 
                field_2_html.gsub(" ",""))

    field_defaults_html = @field_definition.to_html(SpecialTestWrapper.new, MockFormBuilder.new('field_3'), @field_defaults_hash, 'reporting_field_3')
    assert_not_equal(
      %Q{ [ reporting_field_3(field_3) => 
          date[ reporting_field_3_date((field_3)date) => 
            last_login[ reporting_field_3_date_last_login(((field_3)date)last_login) => 
              after[ reporting_field_3_date_last_login_after((((field_3)date)last_login)after) =>  
                ] ] ] ] }.gsub(" ",""), 
                field_defaults_html.gsub(" ",""))
          
    field_defaults_html = @field_definition.to_html(SpecialTestWrapper.new, MockFormBuilder.new('field_3'), @field_definition.fill_out_hash(@field_defaults_hash), 'reporting_field_3')
    assert_equal(
      %Q{ [ reporting_field_3(field_3) => 
          date[ reporting_field_3_date((field_3)date) => 
            last_login[ reporting_field_3_date_last_login(((field_3)date)last_login) => 
              after[ reporting_field_3_date_last_login_after((((field_3)date)last_login)after) =>  
                ] ] ] ] }.gsub(" ",""), 
                field_defaults_html.gsub(" ",""))
                
  end

  def test_fill_out_hash
    assert_equal( {'date' => {
       'last_login' => {'between' => {'after' => '', 'before' => ''},
                      'last_login_select' => 'between'},
       'date_select' => 'last_login'
      },
      'report' => 'date' }, 
      @field_definition.fill_out_hash({'date' => {
        'last_login' => {'last_login_select' => 'between'},
        'date_select' => 'last_login'
       },
       'report' => 'date' }))
    
    assert_equal({"status"=>{
        "status_select"=>""}, "report"=>"status"}, 
      @field_definition.fill_out_hash({}))
      
    assert_equal({"date"=>
        {"last_login"=>{"last_login_select"=>"after", "after"=>{"after"=>""}},
          "date_select"=>"last_login"},
        "report"=>"date"},
        @field_definition.fill_out_hash(@field_defaults_hash))

    assert_equal({"status"=>{
        "status_select"=>"somevalue"}, "report"=>"status"}, 
      @field_definition.fill_out_hash(  {"status"=>{
            "status_select"=>"somevalue"}, "report"=>"status"}))
  end
  
  def test_to_hash_for_json
    #test 'to_hash_for_json' by constructing the array of html ouputs with the help of to_html
    #and verifying that they are the same thing 
    subfield_traversal = Proc.new do |field, hash|
      field.html_out_args.each do |arg|
        hash[arg] = ""
      end
      field.sub_fields.each do |f|
        hash[f.name] = subfield_traversal.call(f, {})
      end
      hash
    end
    dummy_hash = subfield_traversal.call(@field_definition, {})

    json_hash = @field_definition.to_hash_for_json(SpecialTestWrapper.new, MockFormBuilder.new('field_index'), 'reporting_field_index')
    
    json_hash_values = json_hash.values.collect{ |val| val.gsub(/[\[\] ,]+/,"").gsub("=>\n","") }

    array_of_html_outputs = @field_definition.to_html(SpecialTestWrapper.new, MockFormBuilder.new('field_index'), 
                                   dummy_hash, 'reporting_field_index').gsub(/[\[\] ,]+/,"").split("=>\n")
                                   
    json_hash_values.each do |val|
      assert(array_of_html_outputs.include?(val), 
        "#{val} is in the json hash, but was not found in the array of html outputs " +
        " \n json hash is: " + json_hash.to_yaml + " \n array of html outputs is: " + array_of_html_outputs.to_yaml)
    end
    array_of_html_outputs.each do |val|
      assert(json_hash_values.include?(val), 
        "#{val} is in the array of html outputs but not in the json hash " +
        " \n json hash is: " + json_hash.to_yaml + " \n array of html outputs is: " + array_of_html_outputs.to_yaml)
    end
  end
  
  def test_load_query_conditions_and_errors
    collected_errors = QueryBuilder::FieldErrors.new
    assert_equal(["after_value"], @field_definition.load_query_conditions_and_errors(@field_1_hash, collected_errors))
    assert collected_errors.empty?
    
    collected_errors = QueryBuilder::FieldErrors.new
    assert_equal([["between_after_value", "between_before_value"]], @field_definition.load_query_conditions_and_errors(@field_2_hash, collected_errors))
    assert collected_errors.empty?

    collected_errors = QueryBuilder::FieldErrors.new
    assert_equal([], @field_definition.load_query_conditions_and_errors(@raises_errors_hash, collected_errors))
    assert !collected_errors.empty?    
    raises_errors_html = @field_definition.to_html(SpecialTestWrapper.new, MockFormBuilder.new('field_1'), @raises_errors_hash, 'reporting_field_1', collected_errors)
    assert_equal(
      %Q{ [ reporting_field_1(field_1) =>
          date[ reporting_field_1_date((field_1)date) =>
            last_login[ reporting_field_1_date_last_login(((field_1)date)last_login) =>
              after[ ERROR ] ] ] ] }.gsub(" ",""), 
                raises_errors_html.gsub(" ",""))        
  end
  
  def test_load_from_object    
    assert_equal(@field_1_hash, @field_definition.load_from_object(@mock_object_like_field_1))
    assert_equal(@field_2_hash, @field_definition.load_from_object(@mock_object_like_field_2))
  end
  
  def test_load_object_from_hash
    loaded_object_from_field_1_hash = @field_definition.load_object_from_hash(MockObjectLikeFieldHashes.new, @field_1_hash)
    loaded_object_from_field_2_hash = @field_definition.load_object_from_hash(MockObjectLikeFieldHashes.new, @field_1_hash)
    
    [[@mock_object_like_field_1, loaded_object_from_field_1_hash], 
    [@mock_object_like_field_1, loaded_object_from_field_1_hash]].each do |mock_obj, loaded_obj|
      mock_obj.instance_variables.each do |var|
        mock_obj_value = mock_obj.instance_variable_get(var)
        loaded_obj_value = loaded_obj.instance_variable_get(var)
        if mock_obj_value == @@string_we_dont_like_to_see
          assert_equal(nil, loaded_obj_value)
        else
          assert_equal(mock_obj_value, loaded_obj_value)
        end
      end
    end
  end
  
  #status 'active' or 'inactive'
  #date 'last_login' or 'created_at'
  #last_login: 'after' _ 
  #              'within_last' _  + [select: 'days' or 'months']
  # created_at:  'before' _
  #               'between' _ and _  
  def root_field_definition
    default_html = " =>\n "
    QueryBuilder::Field.new do
      
      html_out('report') { |fh, value, sub_fields|
        fh.to_s+default_html+value.to_s
      }
      
      sub_field 'status' do
        html_out('status_select') { |fh, value|
          fh.to_s+default_html+value.to_s
        }
        query_conditions { |value| 
          value
        }
        get_value { |thing|
          thing.status
        }
        set_value { |thing, value|
          #should be:
          #thing.status = value
          #but: 
          raise "based on specific implementation and usage of me in this test, this code should never be called"
          #so we raise an exception to 'assert' that
        }
      end
      
      sub_field 'date' do        
        html_out('date_select') { |fh, value|
          fh.to_s+default_html+value.to_s
        }
        get_value { |thing |
          thing.date_type
        }
        set_value { |thing, value|
          thing.date_type = value
        }
        
        
        some_dates = ['created_at', 'last_login']
        
        some_dates.each do |some_date|
          sub_field "#{some_date}" do
            html_out("#{some_date}_select") { |fh, value|
              fh.to_s+default_html+value.to_s
            }
            sub_field 'after' do
              html_out('after') { |fh, value|
                fh.to_s+default_html + value.to_s
              }
              query_conditions { |value| 
                raise ArgumentError, "got a bad value" if value == @@string_we_dont_like_to_see
                value
              }
              if some_date == 'last_login'
                get_value { |thing |
                  thing.last_login_after
                }
                set_value { |thing, value|
                  thing.last_login_after = value
                }                
              else
                get_value { |thing |
                  thing.created_at_after
                }
                set_value { |thing, value|
                  thing.created_at_after = value
                }               
              end
            end
            sub_field 'within_last' do
              html_out('value', 'range') { |fh, value, range|
                fh.to_s+default_html + value.to_s + "," + range.to_s
              }
              query_conditions { |value, range| 
                [value, range]
              }
            end
            sub_field 'before' do
              html_out('before') { |fh, value|
                fh.to_s+default_html + value.to_s
              }
              query_conditions { |value| 
                value
              }
            end
            sub_field 'between' do
              html_out('after', 'before') { |fh, value_after, value_before|
                fh.to_s+default_html + value_after.to_s + "," + value_before.to_s
              }
              query_conditions { |value_after, value_before| 
                [value_after, value_before]
              }
              if some_date == 'last_login'
                get_value { |thing |
                  [thing.last_login_between_after, thing.last_login_between_before]
                }
                set_value { |thing, value_after, value_before|
                  thing.last_login_between_after = value_after
                  thing.last_login_between_before = value_before
                }
              else
                get_value { |thing |
                  [thing.created_at_between_after, thing.created_at_between_before]
                }                
                set_value { |thing, value_after, value_before|
                  thing.created_at_between_after = value_after
                  thing.created_at_between_before = value_before
                }
              end
            end
          end
        end
        
      end
      
    end
  end
  
  
end
