require './spec/spec_helper'
require './parser/AutoruParser'
describe AutoruParser do
  before {
    @fixture = Nokogiri::HTML::DocumentFragment.parse('<td class="b-selector-list-cell">
            <a href="/cars/ac/used/?mark_id=1#mark_id" class="name">AC</a>
    <span class="m_widget_hint">1</span>
            </td>')
    @parser = AutoruParser.new
  }

  it 'check reading makers list to array' do
    result = @parser.get_cars_makers_array
    expect(result.class).to eq(Array)
    expect(result.size).to be > 200
  end

  it 'check reading maker href from maker html' do
    result = @parser.get_href_from_html(@fixture)
    expect(result).to eq("/cars/ac/used/")
  end

  it 'check reading count from maker html' do
    result = @parser.get_count_from_html(@fixture)
    expect(result).to eq("1")
  end

  it 'check reading name from maker html' do
    result = @parser.get_name_from_html(@fixture)
    expect(result).to eq("AC")
  end

  it 'should create cars makers in redis' do
    @parser.redis.flushall
    @parser.update_cars_makers
    expect((@parser.redis.lrange "makers", 0, -1).size).to be > 200
  end

  it 'should find cars models' do
    @parser.update_cars_makers
    makers = (@parser.redis.lrange "makers", 0, -1).map{|key| @parser.redis.hgetall(key)}
    models = (@parser.get_new_models makers.first)
    expect(models.size).to be > 0
  end

  it 'should get adds from page' do
    maker = {'url_name'=>"\"audi\""}
    model = {'url_name'=>"\"100\""}
    data = [Nokogiri::HTML::DocumentFragment.parse('<td class="b-results-list-sale-details">
            <a href="/cars/used/sale/1009988485-430526.html" class="b-results-list-name">Audi 100 III (C3)  1.8 MT (90 л.с.)</a>
            <div class="b-results-list-sale-price"><strong>25&nbsp;000&nbsp;руб.</strong></div>
            <div>Реутов, Московская обл.</div>
            Седан, 1984&nbsp;г., 11&nbsp;111&nbsp;км, бензин, механика                    </td>')]
    expect((@parser.parse_page_with_adds maker, model, data, false).first).to eq("1009988485-430526")
  end
end