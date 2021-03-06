require 'test_helper'

class EmailNotifierTest < ActiveSupport::TestCase
  include FileSandbox
  
  BUILD_LOG = <<-EOL
    blah blah blah
    something built
    tests passed / failed / etc
  EOL

  def setup
    setup_sandbox

    ActionMailer::Base.deliveries = []

    @project = Project.new(:name => "myproj")
    @project.path = @sandbox.root
    @build = Build.new(@project, 5)
    @previous_build = Build.new(@project, 4)

    @notifier = EmailNotifier.new
    @notifier.emails = ["jeremystellsmith@gmail.com", "jeremy@thoughtworks.com"]
    @notifier.from = 'cruisecontrol@thoughtworks.com'
    
    @project.add_plugin(@notifier, :test_email_notifier)
  end
  
  def teardown
    teardown_sandbox
  end

  def test_do_nothing_with_passing_build
    @notifier.build_finished(@build)
    assert_equal [], ActionMailer::Base.deliveries
  end

  def test_send_email_with_failing_build
    @notifier.build_finished(failing_build)

    mail = ActionMailer::Base.deliveries[0]

    assert_equal @notifier.emails, mail.to
    assert_equal "[CruiseControl] myproj build 5 failed", mail.subject
  end

  def test_send_email_with_fixed_build
    Configuration.stubs(:dashboard_url).returns(nil)
    @build.expects(:output).at_least_once.returns(BUILD_LOG)

    @notifier.build_fixed(@build, @previous_build)

    mail = ActionMailer::Base.deliveries[0]

    assert_equal @notifier.emails, mail.to
    assert_equal "[CruiseControl] myproj build 5 fixed", mail.subject
  end
  
  def test_logging_on_send
    CruiseControl::Log.expects(:event).with("Sent e-mail to 4 people", :debug)
    BuildMailer.expects(:build_report).returns mock(:deliver => true)
    @notifier.emails = ['foo@happy.com', 'bar@feet.com', 'you@me.com', 'uncle@tom.com']
    @notifier.build_finished(failing_build)

    CruiseControl::Log.expects(:event).with("Sent e-mail to 1 person", :debug)
    BuildMailer.expects(:build_report).returns mock(:deliver => true)
    @notifier.emails = ['foo@happy.com']
    @notifier.build_finished(failing_build)

    CruiseControl::Log.expects(:event).never
    BuildMailer.expects(:build_report).never
    @notifier.emails = []
    @notifier.build_finished(failing_build)
  end
  
  def test_useful_errors
    ActionMailer::Base.stubs(:smtp_settings).returns(:foo => 5)
    CruiseControl::Log.expects(:event).with("Error sending e-mail - current server settings are :\n  :foo = 5", :error)
    mock_mail = mock("Email")
    mock_mail.expects(:deliver).raises('oh noes!')
    
    BuildMailer.expects(:build_report).returns mock_mail
    
    @notifier.emails = ['foo@crapty.com']
    
    assert_raise_with_message(RuntimeError, 'oh noes!') do
      @notifier.build_finished(failing_build)
    end
  end

  def test_configuration_email_from_should_be_used_when_notifier_from_is_not_specified
    Configuration.expects(:email_from).returns('central@foo.com')
    @notifier.from = nil
    build = failing_build()
    
    BuildMailer.expects(:build_report).with(build, ['jeremystellsmith@gmail.com', 'jeremy@thoughtworks.com'],
                        'central@foo.com', 'myproj build 5 failed', 'The build failed.').returns mock(:deliver => true)

    @notifier.build_finished(failing_build)
  end

  def test_notification_mail_should_provide_build_url
    Configuration.stubs(:dashboard_url).returns("http://www.my.com")
    @notifier.emails = ['foo@happy.com']
    @notifier.build_finished(failing_build)
    
    mail = ActionMailer::Base.deliveries[0]
    assert_match /http:\/\/www.my.com\/builds\/myproj\/5/, mail.body.to_s
  end

  def test_notification_mail_should_list_build_info_if_dashboard_url_is_not_set
    Configuration.stubs(:dashboard_url).returns(nil)
    @notifier.emails = ['foo@happy.com']
    @notifier.build_finished(failing_build)

    mail = ActionMailer::Base.deliveries[0]
    assert_match /Note: if you set Configuration\.dashboard_url in site_config\.rb/, mail.body.to_s
  end

  private
  
  def failing_build
    @build.stubs(:failed?).returns(true)
    @build.stubs(:output).returns(BUILD_LOG)
    @build
  end
end
