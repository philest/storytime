#  app.rb                                     Phil Esterman     
# 
#  The routes controller. Uses helpers to reply to SMS. 
#  --------------------------------------------------------

#########  DEPENDENCIES  #########

#config the load path 
require 'bundler/setup'

#siantra dependencies 
require 'sinatra/base'
require "sinatra/reloader"


require 'twilio-ruby'

#for access in views
require_relative '../config/initializers/aws'

#helpers
require_relative '../helpers/routes_helper'
require_relative '../helpers/school_code_helper'

# Error tracking. 
require 'airbrake'
require_relative '../config/initializers/airbrake'

require 'sinatra/flash'

class App < Sinatra::Base
  set :root, File.join(File.dirname(__FILE__), '../')
  register Sinatra::Flash

  configure :development do
    register Sinatra::Reloader
  end

  configure :production do
    require 'newrelic_rpm'
    set :static_cache_control, [:public, :max_age => 600]
  end

  before do
    headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
    headers['Access-Control-Allow-Origin'] = "#{ENV['enroll_url']}"
    headers['Access-Control-Allow-Headers'] = 'accept, authorization, origin'
    headers['Access-Control-Allow-Credentials'] = 'true'
  end


  use Airbrake::Rack::Middleware


  #set mode (production or test)
  MODE ||= ENV['RACK_ENV']
  PRO ||= "production"
  TEST ||= "test"

  #########  ROUTES  #########

  # Admin authentication, from Sinatra.
  include RoutesHelper
  helpers RoutesHelper
  helpers SchoolCodeMatcher

  set :session_secret, "328479283uf923fu8932fu923uf9832f23f232"
  enable :sessions

  # use Rack::Session::Cookie, :key => 'rack.session',
                             # :path => '/',
                             # :secret => 'your_secret'

  #root
  get '/' do
    case session[:role]
    when 'admin'
      redirect to '/admin_dashboard'
    when 'teacher'
      redirect to '/dashboard'
    else
      erb :main_new
    end 
  end

  get '/test' do
    UnionWorker.perform_async
  end

  get '/test_dashboard' do
    session[:educator] = { "id"=>1, "name"=>nil, "email"=>"david.mcpeek@yale.edu", "signature"=>"Mr. McPeek", "code"=>nil }
    session[:role] = 'admin'
    session[:school] = {"id"=>39, "name"=>"Rocky Mountain Prep", "code"=>"RMP|RMP-es", "signature"=>"RMP"}
    get_url = ENV['RACK_ENV'] == 'production' ? ENV['enroll_url'] : 'http://localhost:4567/enroll'
    data = HTTParty.get("#{get_url}/teachers/#{session[:educator]['id']}")
    puts "data dashboard = #{data.body.inspect}"
    erb :admin_dashboard, :locals => {:teachers => JSON.parse(data)}
  end



  get '/user_exists' do
    puts "params=#{params}"

    res = HTTParty.get(
      "#{ENV['enroll_url']}/user_exists",
      query: {
        password: params['password'],
        email: params['email']
      }
    )
    puts res.inspect
    return res.parsed_response
  end


  get '/dashboard' do
    if session[:educator].nil?
      redirect to '/'
    end
    puts "session[:educator] = #{session[:educator]}"

    get_url = ENV['RACK_ENV'] == 'production' ? ENV['enroll_url'] : 'http://localhost:4567/enroll'
    data = HTTParty.get("#{get_url}/users/#{session[:educator]['id']}")
    puts "data dashboard = #{data.body.inspect}"

    erb :dashboard, :locals => {:users => JSON.parse(data)}
  end


  get '/admin_dashboard' do
    if session[:educator].nil?
      redirect to '/'
    end
    puts "session[:educator] = #{session[:educator]}"
    puts "session[:school] = #{session[:school]}"
    get_url = ENV['RACK_ENV'] == 'production' ? ENV['enroll_url'] : 'http://localhost:4567/enroll'
    data = HTTParty.get("#{get_url}/teachers/#{session[:educator]['id']}")
    puts "data dashboard = #{data.body.inspect}"
    if data.body != "[]"
      puts "normal admin dashboard"
      erb :admin_dashboard, :locals => {:teachers => JSON.parse(data), school_users: nil}
    else # this is a school with no teachers....
      # so check for students
      get_url = ENV['RACK_ENV'] == 'production' ? ENV['enroll_url'] : 'http://localhost:4567/enroll'
      data = HTTParty.get("#{get_url}/school/users/#{session[:educator]['id']}")
      puts "data_dashboard2.0 = #{data.body.inspect}"
      puts "data = #{JSON.parse(data)}"
      if data != "" # go to the SPECIAL school_dashboard
        # process locals somehow.........
        puts "user admin dashboard"
        erb :admin_dashboard, :locals => {:school_users => JSON.parse(data)}
      else # regular admin dashboard with no teachers...... :(
        puts "normal admin dashboard"
        erb :admin_dashboard, :locals => {:teachers => JSON.parse(data), school_users: nil}
      end
    end
  end

  get '/signup/spreadsheet' do
    if session[:educator].nil?
      redirect to '/'
    end

    erb :spreadsheet
  end

  get '/logout' do
    session[:educator] = nil
    session[:school] = nil
    session[:role] = nil

    redirect to '/'
  end

  post '/signup/spreadsheet' do
    # Check if user uploaded a file
    if params['spreadsheet'] && params['spreadsheet'][:filename] && !session[:educator].nil?
      filename = params['spreadsheet'][:filename]
      file = params['spreadsheet'][:tempfile]

      teacher_assets = S3.bucket('teacher-materials')
      if teacher_assets.exists?
        name = "teacher-uploads/#{session[:educator]['signature']}/#{filename}"

        if teacher_assets.object(name).exists?
            puts "#{name} already exists in the bucket"
        else
          obj = teacher_assets.object(name)
          obj.put(body: file, acl: "public-read")
          puts "Uploaded '%s' to S3!" % name
        end
      end
      # dirname = "./public/uploads/#{session[:educator]['signature']}"
      # unless File.directory?(dirname)
      #   FileUtils.mkdir_p(dirname)
      # end
      # path = "#{dirname}/#{filename}"

      # # Write file to disk
      # File.open(path, 'wb') do |f|
      #   f.write(file.read)
      # end
    end

    Pony.mail(:to => 'phil.esterman@yale.edu,david@joinstorytime.com',
              :cc => 'aubrey.wahl@yale.edu',
              :from => 'david.mcpeek@yale.edu',
              :subject => "ST: #{session[:educator]['signature']} uploaded a spreadsheet",
              :body => "Check it out. #{filename}")
    flash[:spreadsheet] = "Congrats! We'll send your class a text in a few days."
    redirect to '/signup/spreadsheet'

  end


  # http://localhost:4567/signin?admin=david.mcpeek@yale.edu&school=rmp
  # 
  # http://localhost:4567/signin?email=david.mcpeek@yale.edu&school=rmp&name=David+McPeek
  # 
  # http://joinstorytime.com/signin?school=rmp&email=aperricone@rockymountainprep.org&name='Mrs. Perricone'


  # need to update this for new roles.....
  # need to have a role parameter
  # 
  get '/signin' do
    puts "signin params = #{params}"
    school_code = params['school']
    email       = params['email']
    signature   = params['name']
    role        = params['role']
    first_name  = params['first_name']
    last_name   = params['last_name']

    if params['admin'] == 'james@rockymountainprep.org'
      signature, email, role = 'James Cryan', 'james@rockymountainprep.org', 'admin'
    elsif params['admin'] == 'athompson@rockymountainprep.org'
      signature, email, role = 'Angelin Thompson', 'athompson@rockymountainprep.org', 'admin'
    elsif params['email'].include? 'rockymountainprep' 
      # everyone else at RMP's a teacher
      role = 'teacher'
    end

    post_url = ENV['RACK_ENV'] == 'production' ? ENV['enroll_url'] : 'http://localhost:4567/enroll'
    puts "post_url = #{post_url}"
    data = HTTParty.post(
      "#{post_url}/signup", 
      body: {
        signature: signature,
        email: email,
        password: school_code,
        role: role,
        first_name: first_name,
        last_name: last_name
      }
    )
    puts "data = #{data.code.inspect}"

    if data.code == 500 or data.code == 501
      flash[:signin_error] = "Incorrect login information. Check with your administrator for the correct school code!"
      redirect to '/'
      # return 
    end

    data = JSON.parse(data)

    puts data

    if data["secret"] != 'our little secret'
      flash[:signin_error] = "Incorrect login information. Check with your administrator for the correct school code!"
      redirect to '/'
    end

    # puts params
    session[:educator] = data['educator']
    # session[:educator]  = data['teacher']
    session[:school]   = data['school']
    session[:users]    = data['users']
    session[:role]     = data['role']
    # session[:educator]    = data['admin']

    puts session.inspect

    if session['educator'].nil?
      # maybe have a banner saying, "must log in through teacher account"
      flash[:signin_error] = "Incorrect login information. Check with your administrator for the correct school code!"
      redirect to '/'
    end

    case session['role']
    when 'admin'
      puts "going to admin dashboard"
      if params['invite']
        redirect to '/admin_dashboard?invite=' + params['invite']
      else
        redirect to '/admin_dashboard'
      end


      redirect to '/admin_dashboard'
    when 'teacher'
      puts "going to teacher dashboard"
      if params['flyers']
        redirect to '/dashboard?flyers=' + params['flyers']
      else
        redirect to '/dashboard'
      end
    end

  end

   
  # users sign in. posted from st-enroll.
  post '/signin' do
    puts "params = #{params}"
    post_url = ENV['RACK_ENV'] == 'production' ? ENV['enroll_url'] : 'http://localhost:4567/enroll'
    puts "post_url = #{post_url}"
    data = HTTParty.post(
      "#{post_url}/signup", 
      body: params
    )
    puts "data = #{data.code.inspect}"

    if data.code == 500 or data.code == 501
      flash[:signin_error] = "Incorrect login information. Check with your administrator for the correct school code!"
      redirect to '/'
      # return 
      puts "ass me!!!!!!!"
    end

    data = JSON.parse(data)

    puts data

    if data["secret"] != 'our little secret'
      flash[:signin_error] = "Incorrect login information. Check with your administrator for the correct school code!"
      redirect to '/'
    end

    # puts params
    session[:educator] = data['educator']
    session[:school]  = data['school']
    session[:users]   = data['users']
    # session[:educator]   = data['admin']
    session[:role]    = data['role']

    puts session.inspect

    # redirect to '/signup'

    if session['educator'].nil?
      # maybe have a banner saying, "must log in through teacher account"
      flash[:signin_error] = "Incorrect login information. Check with your administrator for the correct school code!"
      redirect to '/'
    end

    case session['role']
    when 'admin'
      puts "going to admin dashboard"

      if params['invite']
        redirect to '/admin_dashboard?invite=' + params['invite']
      else
        redirect to '/admin_dashboard'
      end

    when 'teacher'
      puts "going to teacher dashboard"
      if params['flyers']
        redirect to '/dashboard?flyers=' + params['flyers']
      else
        redirect to '/dashboard'
      end
    end

  end


  get '/:class_code/class' do
    # teacher code, right?
    # right now we're searching by teacher_id
    
    # get_teacher() <- from st-enroll, i suppose, unless we get the db over here.

    # get teacher, then get language

    


    teacher = Teacher.where(id: params[:teacher_id]).first
    if teacher.nil?
      return
      # erb :fail_page
    end


    school = teacher.school

    session[:teacher_id] = teacher.id 
    session[:teacher_sig] = teacher.signature
    session[:school_id] = school.id
    session[:school_sig] = school.signature


    school = "ST Elementary"

    session[:teacher_id] = 1
    session[:teacher_sig] = "Mr. McPeek"
    session[:school_id] = 1
    session[:school_sig] = "ST Elementary"

    erb :register, locals: {teacher: "Mr. McPeek", school: "ST Elementary"}

  end

  post '/register' do
    puts "#{params}"
    # get user data from POST params
    # create user
    # session[:user_id] = new_user.id
    redirect to '/register/role'
  end


  get '/register/role' do
    erb :role
  end

  post '/register/role' do
    puts "in register/role"
    # get role, save it in user record 
    redirect to '/register/password'
  end


  get '/register/password' do
    erb :password
  end




  post '/register/password' do
    # get params
    # encrypt/store password

    redirect to  '/register/app'

  end



  get '/register/app' do
    erb :'get-app'
  end




  get '/signup' do
    if session['educator'].nil?
      # maybe have a banner saying, "must log in through teacher account"
      flash[:signin_error] = "Incorrect login information. Check with your administrator for the correct school code!"
      redirect to '/'
    end

    case session['role']
    when 'admin'
      puts "going to admin dashboard"

      if params['invite']
        redirect to '/admin_dashboard?invite=' + params['invite']
      else
        redirect to '/admin_dashboard'
      end

    when 'teacher'
      puts "going to teacher dashboard"
      if params['flyers']
        redirect to '/dashboard?flyers=' + params['flyers']
      else
        redirect to '/dashboard'
      end

    end

  end



  get '/privacy' do
    erb :privacy_policy
  end

  get '/terms' do
    erb :terms
  end

  get '/illustration-guide' do
    redirect to "https://docsend.com/view/vnndn8z"
  end 

  get '/poetry-guide' do
    redirect to "https://docsend.com/view/ij6bbnr"
  end 




  post '/success' do
    puts params.to_s  
    return params.to_s
  end

  get '/:code/class' do
    erb :maintenance
  end


  # post '/success' do  
    # create_invite(params) 
    # erb :success
  # end

  post '/demo_success' do 
    notify_demo(params)
    redirect to('/')
  end


  get '/read' do
    redirect to('/signup')
  end

  get '/start' do
    redirect to('/signup')
  end

  get '/go' do
    redirect to('http://m.me/490917624435792')
  end


  # Documenation. 
  get '/doc/' do 
    File.read(File.join('public', 'doc/_index.html'))
  end

  get '/doc' do
    redirect to('/doc/')
  end

  # Resources
  get '/resources' do 
    protected!
    erb :resources
  end

  get '/resources/' do 
    redirect to('/resources')
  end 

  get '/team' do 
    erb :team
  end

  get '/case_study' do 
    erb :case_study
  end

  get '/join' do 
    erb :job_board
  end

  get '/product_lead' do 
    erb :"jobs/product"
  end

  get '/developer' do 
    erb :"jobs/developer"
  end 

  get '/pilots' do 
    erb :"jobs/pilots"
  end 

  get '/schools' do 
    erb :"jobs/schools"
  end 

  get '/illustrator' do 
    erb :"jobs/illustrator"
  end 

  get '/design' do 
    erb :"jobs/design"
  end 


  post '/get_updates_form_success' do 
    create_follower(params)
    redirect to('/join')
  end

  post '/enroll_teachers_form_success' do
    puts "contact info params = #{params}"

    HTTParty.post(
      "#{ENV['enroll_url']}/invite_teachers",
      body: params
    )
    # Pony.mail(:to => 'supermcpeek@gmail.com',
    #           :cc => '',
    #           :from => 'supermcpeek@gmail.com',
    #           :subject => "An admin invited teachers",
    #           :body => "#{params}")

    Pony.mail(:to => 'phil.esterman@yale.edu,supermcpeek@gmail.com,aawahl@gmail.com',
                :from => 'david@joinstorytime.com',
                :headers => { 'Content-Type' => 'text/html' },
                :subject => "An admin #{params['admin_sig']} from #{params['school_sig']} invited teachers",
                :body => params)
   

    flash[:teacher_invite_success] = "Congrats! We'll send your teachers an invitation to join StoryTime."
    session[:educator]['signin_count'] += 1

    redirect to '/admin_dashboard'
  end

  get '/teacher/visited_page' do
    session[:educator]['signin_count'] += 1
    status 200
    return session[:educator]['signin_count'].to_s
  end


  get '/reset' do
    session[:educator]['signin_count'] = 0
    status 200
    return session[:educator]['signin_count'].to_s
  end

  post '/enroll_families_form_success' do 

    enroll_families(params)
    erb :internal_success
  end


  get '/signup/flyer' do
    if session[:educator].nil?
      redirect to '/'
    end

    erb :flyer
  end

  get '/signup/in-person' do
    if session[:educator].nil?
      redirect to '/'
    end

    puts "session = #{session.inspect}"
    erb :inperson
  end



  # redirect to Messenger app. 
  get '/books' do
    redirect to('http://m.me/490917624435792')
  end

  get '/rayna' do
    redirect to('https://www.youtube.com/watch?v=fjwSdLfkPOg&feature=youtu.be')
  end


  #twilio failed: no valid response for sms.
  get '/failed' do
      TwilioHelper.smsRespondHelper("StoryTime: Hi! " + 
          "We're updating StoryTime now and are offline, " +
          "but check back in the next day!")
  end

  #voice call
  get '/called' do
    Twilio::TwiML::Response.new do |r|
      r.Play "http://www.joinstorytime.com/mp3"
    end.text
  end



   
  get '/mp3' do
      send_file File.join(settings.public_folder, 
                              'storytime_message.mp3')
  end

end
