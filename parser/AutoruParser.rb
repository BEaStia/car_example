require './parser/parser_helper'
require 'nokogiri'
require 'redis'
require 'json'
require 'mongo'
require 'open-uri'

class AutoruParser < BaseParser

  MAKERS_URL = "http://m.auto.ru/cars/used/mark/?"
  MODELS_URL = lambda {|name| "http://m.auto.ru/cars/" + JSON.load(name) + "/used/model/?"}
  PAGE_URL = lambda {|maker, model, page| "http://m.auto.ru/cars/#{JSON.load(maker)}/#{JSON.load(model)}/used/?p=#{page}"}
  ADD_URL = lambda {|id| "http://m.auto.ru/cars/used/sale/#{id}.html"}
  PHONE_URL = lambda {|id| "http://m.auto.ru/cars/used/phones/#{id}"}

  def initialize use_proxy = false, use_em = false
    @redis = Redis.new
    @mongo = Mongo::Client.new('mongodb://127.0.0.1:27017/temp')
    if use_proxy
      @proxy = {
          :proxy=>{
              :host => "http://localhost",
              :port => 9150
          }
      }
    else
      @proxy = {}
    end

    if use_em
      @em = true
    end
  end

  def redis
    @redis
  end

  def mongo
    @mongo
  end

  def get_page_count model
    JSON.load(model['count']).to_i / 10 + 1
  end

  def get_page_with_adds maker, model, index
    url = PAGE_URL.call(maker['url_name'], model['url_name'], index)
    data = get_info_array(url, ".b-results-list-sale-details")
    parse_page_with_adds maker, model, data
  end

  def parse_page_with_adds maker, model, data, write_to_db = true
    data.map!{|item|
      advertisement_id = (get_href_from_html item).split("/")[4].split(".").first
      parent_key = "maker_#{JSON.load maker['url_name']}_model_#{JSON.load model['url_name']}"
      redis.rpush(parent_key, advertisement_id)
      advertisement_id
    }
    if !data.empty? && write_to_db
      get_adds_from_page maker, model, data
    end
    data
  end

  def get_adds_from_page maker, model, data
    data.map!{|adv_id| [adv_id, ADD_URL.call(adv_id)]}
    if @em
      EventMachine.run do
        multi = EventMachine::MultiRequest.new
        data.each{|arr|
          multi.add(arr[0] , EventMachine::HttpRequest.new(arr[1], @proxy).get(:redirects => 3))
        }
        multi.callback {
          multi.responses[:callback].each{|key, response|
            parse_add_page(maker, model, key, response.response)
          }
          multi.responses[:errback].each{|key,value|
            Em.stop
            parse_add_page maker, model, key, open(url).read
          }
          EventMachine.stop
        }
      end
    else
      data.each{|arr|
        parse_add_page maker, model, arr[0], open(arr[1]).read
      }
    end
  end

  def get_new_cars
    makers = (redis.lrange "makers", 0, -1).map{|key| redis.hgetall(key)}
    makers.each{|maker|
      get_cars_models maker
      models = redis.lrange "maker_#{JSON.load maker['url_name']}_models", 0, -1
      models.map!{|model| redis.hgetall(model) }.each{|model|
        unless JSON.load(model['count']).to_i.eql?(0)
          pages_count = get_page_count model
          (1..pages_count).each{|index|
            get_page_with_adds maker, model, index
          }
        end
      }
    }
  end

  def get_new_models maker
    (get_car_model_array maker).map{|item|
      {
          :url_name => get_href_from_html(item).split('/')[3],
          :href => get_href_from_html(item),
          :name => get_name_from_html(item).strip,
          :count => get_count_from_html(item)
      }
    }.each{|model_hash|
      list_key = "maker_#{JSON.load(maker['url_name'])}_models"
      model_key = "model_#{JSON.load(maker['url_name'])}_#{model_hash[:url_name]}"
      redis.rpush(list_key, model_key)
      redis.hset(model_key, "count", model_hash[:count].to_json)
      redis.hset(model_key, "name", model_hash[:name].to_json)
      redis.hset(model_key, "url", model_hash[:href].to_json)
      redis.hset(model_key, "url_name", model_hash[:url_name].to_json)
    }
  end

  def parse_add_page maker, model, id, html
    page = Nokogiri.HTML(html)
    attributes = {}
    attrs_trs = page.css('.b-sale-details-list tr')
    attrs_trs.each{|tr|
      attributes[tr.css('.b-sale-details-n').text.strip.split(':').first] = tr.css('.b-sale-details-v').text.strip
    }
    attributes.select!{|key,value| !value.nil? && !value.empty? && !key.nil?}
    attributes['Телефоны'] = get_phone_number id
    attributes['Производитель'] = JSON.load maker['name']
    attributes['Модель'] = JSON.load model['name']
    attributes['Time'] = Time.now.to_i
    mongo[:adds].insert_one attributes
    p attributes

  end

  def update_cars_makers
    get_cars_makers_array.map{|item| {:url_name => get_href_from_html(item).split('/')[2],
                                      :href => get_href_from_html(item),
                                      :name => get_name_from_html(item),
                                      :count => get_count_from_html(item) }
    }.each{|maker_hash|
      key = "maker_#{maker_hash[:url_name]}"
      redis.lrem "makers", 1, key
      redis.rpush "makers", key
      redis.hset(key, "count", maker_hash[:count].to_json)
      redis.hset(key, "name", maker_hash[:name].to_json)
      redis.hset(key, "url", maker_hash[:href].to_json)
      redis.hset(key, "url_name", maker_hash[:url_name].to_json)
    }
  end

  def get_href_from_html html
    html.css('a').attr('href').text.split('?').first
  end

  def get_name_from_html html
    html.text.split("\n").map(&:strip).select{|item| !item.empty?}.first
  end

  def get_count_from_html html
    html.text.split("\n").map(&:strip).select{|item| !item.empty?}[1]
  end

  def get_cars_makers_array
    get_info_array(MAKERS_URL, ".b-selector-list-cell").select{|data| !data.css('a').to_a.empty?}
  end

  def get_info_array url, selector
    data = []
    if @em
      EM.run do
        http = EM::HttpRequest.new(url).get
        http.errback { p 'Uh oh'; EM.stop }
        http.callback do
          EventMachine.stop
          result = Nokogiri.HTML(http.response)
          data = result.css(selector).to_a
        end
      end
    else
      begin
        response = Nokogiri.HTML open(url).read
        data = response.css(selector).to_a
      rescue Error=>error
        p "real error happened"
      end
    end
    data
  end

  def get_car_model_array maker
    url = MODELS_URL.call(maker['url_name'])
    p url
    get_info_array(url, ".b-selector-list-cell").select{|data| !data.css('a').to_a.empty?}
  end

  def get_phone_number aid
    PHONE_URL.call(aid)
  end

  def get_cars_models maker
    get_new_models maker
  end
end