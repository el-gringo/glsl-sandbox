
class Effects
    def initialize(effects, extra={})
        @effects=effects
        @extra={
            :page => 0,
            :count => 0,
            :effects_per_page => EFFECTS_PER_PAGE
        }.merge(extra)
    end

    def bind
        binding
    end

    def effects
        @effects
    end

    def extra
        @extra
    end

    def previous_page
        if @extra[:page]>0
            @extra[:page]-1
        end
    end

    def next_page
        if @extra[:count]>=((@extra[:page]+1)*@extra[:effects_per_page])
            @extra[:page]+1
        end
    end

    def image(effect)
        if effect["image_url"]
            effect["image_url"]
        else
            effect["image"]
        end
    end
end

class GlslDatabase
    def initialize
        connect_database
        initialize_counter
    end

    def increment_code_counter
        counter=@counters.find_one_and_update(
            {:_id => 'code'}, {'$inc' => {:counter => 1}}
        )

        counter['counter']
    end

    def save_version(code_id, code)
        time=Time.now
        code_data=JSON.parse(code)

        data={
            :created_at => time,
            :code => code_data['code']
        }

        if false
          res=Cloudinary::Uploader.upload(
              code_data['image'],
              :public_id => code_id.to_s)

          image_url=res['url']
        end

        @code.find_one_and_update({ :_id => code_id },
            {
                '$set' => {
                    :modified_at    => time,
                    :image => code_data['image']
                },
                '$push' => { :versions => data }
            }
        )

        code=$glsl.get_code(code_id)

        version=code['versions'].length-1

        "#{code_id}.#{version}"
    end

    def save_effect(code)
        code_data=JSON.parse(code)

        if code_data['code_id'] && !code_data['code_id'].empty?
            m=code_data['code_id'].match(/^(\d+)(\.\d+)?/)
            if m
                save_version(m[1].to_i, code)
            else
                save_new_effect(code)
            end
        else
            save_new_effect(code)
        end
    end

    def save_new_effect(code)
        counter=increment_code_counter

        code_data=JSON.parse(code)

        data={
            :_id => counter,
            :created_at => Time.now,
            :modified_at => Time.now,
            :versions => [],
            :user => code_data['user']
        }

        if code_data['parent']
            m=code_data['parent'].match(%r{^(\d+)(\.(\d+))?})
            data[:parent] = m[1].to_i if m
            data[:parent_version] = m[3].to_i if m && m[3]
        end

        @code.insert_one(data)

        save_version(counter, code)
    end

    def get_page(page=0, effects_per_page=50)
        count=@code.count()

        effects=@code.find({})
          .sort({modified_at: -1})
          .limit(effects_per_page)
          .skip(page*effects_per_page)
        
        ef=Effects.new(effects,
            :page   => page,
            :count  => count
        )

        ef
    end

    def get_code(id)
        @code.find({:_id => id}).first
    end

    def get_code_json(id, version=nil)
        code=get_code(id)

        if code
            if version
                item=code['versions'][version]
            else
                item=code['versions'].last
            end
            
            if code['user']
                user=code['user']
            else
                user=false
            end

            parent=nil
            if code['parent']
                parent="/e##{code['parent']}"
                parent+=".#{code['parent_version']}" if code['parent_version']
            end
        else
            item=nil
        end

        if item
            data={
                :code => item['code'],
                :user => user,
                :parent => parent
            }.to_json
        else
            {
                :code => '// item not found',
                :user => false
            }.to_json
        end
    end

private

    def connect_database
        uri = URI.parse(ENV['MONGOHQ_URL'])
        ENV['MONGOID_HOST'] = uri.host
        ENV['MONGOID_PORT'] = uri.port.to_s
        ENV['MONGOID_USERNAME'] = uri.user
        ENV['MONGOID_PASSWORD'] = uri.password
        ENV['MONGOID_DATABASE'] = uri.path.gsub('/', '')
        
        client = Mongo::Client.new(ENV['MONGOHQ_URL'])
        @db = client.database

        @versions=@db.collection('versions')
        @code=@db.collection('code')
        @counters=@db.collection('counters')
    end

    def initialize_counter
        code=@counters.find({:_id => 'code'}).first
        if !code
            @counters.insert_one({
                :_id => 'code',
                :counter => 0
            })
        end
    end
end
