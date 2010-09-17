class QueryBuilder::FieldWrapper
  attr_accessor :show_remove_link
  
  def initialize(show_remove_link = true)
    @show_remove_link = show_remove_link
  end
  
  def wrap(css_id, depth, to_wrap, in_error = false)
    css_class = (in_error)? "field_error" : ""
    if depth == 0
      to_return = "<div class='#{css_class}' id='#{css_id}'>#{to_wrap}"
      if show_remove_link
        to_return += %Q{<a href="#" class="remove_link" onclick="query_builder_remove_field('#{css_id}');return false;">remove</a>}
      end
      to_return += "</div>"
    else
      "<span class='#{css_class}' id='#{css_id}'>#{to_wrap}</span>"    
    end
  end
  
end