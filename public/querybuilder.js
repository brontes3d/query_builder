function create_query_builder(string_prefix, field_count, json_field_hash)
{
	window[string_prefix+'field_count'] = field_count;
	window[string_prefix+'json_field_hash'] = json_field_hash;  
}
function query_builder_on_change(element){
	prefix = element.parentNode.id.substring(0, element.parentNode.id.indexOf("field_"));
	eopts = element.options;
	for(i=0; i<eopts.length; i++)
	{
		val = eopts[i].value;
		if(val != "")
		{
			to_remove = element.parentNode.childNodes;
			for(j=0; j<to_remove.length; j++)
			{
				if(to_remove[j] != element && to_remove[j].id && to_remove[j].id.indexOf(prefix+"field_") == 0)
				{
					Element.remove(to_remove[j]);
				}
			}
		}
	}
	element_id = element.parentNode.id + "_" + element.value;
	if(element.parentNode.childNodes.length > 1)
	{
		Element.insert(element.parentNode.childNodes[1], { before: query_builder_lookup_markup_for_element_id(prefix,element_id) });
	}
	else
	{
		Element.insert(element.parentNode.id, query_builder_lookup_markup_for_element_id(prefix,element_id));
	}
}
function query_builder_lookup_markup_for_element_id(prefix,element_id)
{
	lookup_by = element_id.replace(/field_[0-9]+/g, "field_index")
	field_current_index = element_id.match(/field_[0-9]+/)[0];
	resulting_markup = window[prefix+'json_field_hash'][lookup_by];
	if(resulting_markup)
	{
		return resulting_markup.replace(/field_index/g, field_current_index);
	}
	else
	{
		return "";
	}
}
function query_builder_remove_field(field_name)
{
	Element.remove(field_name);
}
function query_builder_add_field(prefix)
{
	value = window[prefix+'json_field_hash'][prefix+'field_index'];
	insert_value = value.replace(/field_index/g, 'field_'+(window[prefix+'field_count']+1));
	field_count = window[prefix+'field_count'];
	element_to_insert_after = false;
	while(!element_to_insert_after && field_count > -1)
	{
	  element_to_insert_after = $(prefix+'field_'+field_count);
	  field_count--;
	}
	if(!element_to_insert_after)
	{
		element_to_insert_after = $(prefix+'query_builder_placeholder');
	}
	Element.insert(element_to_insert_after, { after: insert_value });
	window[prefix+'field_count'] += 1;
}
