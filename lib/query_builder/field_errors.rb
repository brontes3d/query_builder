class QueryBuilder::FieldErrors
  
  def initialize
    @errors = {}
  end
  
  def empty?
    @errors.empty?
  end
  
  def add_error(field, error)
    @errors[field] = error
  end
  
  def error_on?(field)
    @errors[field]
  end
  
  def each(&block)
    @errors.each do |field, error|
      yield field.name, error.message
    end
  end
  
end