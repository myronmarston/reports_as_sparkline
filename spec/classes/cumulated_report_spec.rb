require File.join(File.dirname(__FILE__), '..', 'spec_helper')

describe Kvlr::ReportsAsSparkline::CumulatedReport do

  before do
    @report = Kvlr::ReportsAsSparkline::CumulatedReport.new(User, :cumulated_registrations)
  end

  describe '#run' do

    it 'should cumulate the data' do
      @report.should_receive(:cumulate).once

      @report.run
    end

    it 'should return an array of the same length as the specified limit when :live_data is false' do
      @report = Kvlr::ReportsAsSparkline::CumulatedReport.new(User, :cumulated_registrations, :limit => 10, :live_data => false)

      @report.run.length.should == 10
    end

    it 'should return an array of the same length as the specified limit + 1 when :live_data is true' do
      @report = Kvlr::ReportsAsSparkline::CumulatedReport.new(User, :cumulated_registrations, :limit => 10, :live_data => true)

      @report.run.length.should == 11
    end
    
    describe "a month report with a limit of 2" do
      before(:all) do
        User.delete_all
        User.create!(:login => 'test 1', :created_at => Time.now,           :profile_visits => 2)
        User.create!(:login => 'test 2', :created_at => Time.now - 1.month, :profile_visits => 1)
        User.create!(:login => 'test 3', :created_at => Time.now - 3.month, :profile_visits => 2)
        User.create!(:login => 'test 4', :created_at => Time.now - 3.month, :profile_visits => 3)
        User.create!(:login => 'test 5', :created_at => Time.now - 4.month, :profile_visits => 4)
        
        @report2 = Kvlr::ReportsAsSparkline::CumulatedReport.new(User, :cumulated_registrations,
          :grouping => :month,
          :limit => 2
        )

        @one_month_ago    = Date.new(DateTime.now.year, DateTime.now.month, 1) - 1.month
        @two_months_ago   = Date.new(DateTime.now.year, DateTime.now.month, 1) - 2.months
        @three_months_ago = Date.new(DateTime.now.year, DateTime.now.month, 1) - 3.months
      end
      
      it 'should include the counts from before the first period in the cumulated totals' do
        @report2.run.should == [[@two_months_ago, 3.0], [@one_month_ago, 4.0]]
      end
      
      it 'should return the initial count for initial_cumulative_value' do
        options = @report2.send(:options_for_run, {})
        tomorrow = 1.day.from_now
        @report2.send(:initial_cumulative_value, tomorrow,            options).should == 5
        @report2.send(:initial_cumulative_value, tomorrow - 1.month,  options).should == 4
        @report2.send(:initial_cumulative_value, tomorrow - 2.months, options).should == 3
        @report2.send(:initial_cumulative_value, tomorrow - 3.months, options).should == 3
        @report2.send(:initial_cumulative_value, tomorrow - 4.months, options).should == 1
        @report2.send(:initial_cumulative_value, tomorrow - 5.months, options).should == 0
      end
    end

    for grouping in [:hour, :day, :week, :month] do

      describe "for grouping #{grouping.to_s}" do

        [true, false].each do |live_data|

          describe "with :live_data = #{live_data}" do

            before(:all) do
              User.delete_all
              User.create!(:login => 'test 1', :created_at => Time.now - 1.send(grouping), :profile_visits => 1)
              User.create!(:login => 'test 2', :created_at => Time.now - 3.send(grouping), :profile_visits => 2)
              User.create!(:login => 'test 3', :created_at => Time.now - 3.send(grouping), :profile_visits => 3)
            end

            describe do

              before do
                @grouping = Kvlr::ReportsAsSparkline::Grouping.new(grouping)
                @report = Kvlr::ReportsAsSparkline::CumulatedReport.new(User, :cumulated_registrations,
                  :grouping  => grouping,
                  :limit     => 10,
                  :live_data => live_data
                )
                @result = @report.run
              end

              it "should return an array starting reporting period (Time.now - limit.#{grouping.to_s})" do
                @result.first[0].should == Kvlr::ReportsAsSparkline::ReportingPeriod.new(@grouping, Time.now - 10.send(grouping)).date_time
              end

              if live_data
                it "should return data ending with the current reporting period" do
                  @result.last[0].should == Kvlr::ReportsAsSparkline::ReportingPeriod.new(@grouping).date_time
                end
              else
                it "should return data ending with the reporting period before the current" do
                  @result.last[0].should == Kvlr::ReportsAsSparkline::ReportingPeriod.new(@grouping).previous.date_time
                end
              end

            end

            it 'should return correct data for aggregation :count' do
              @report = Kvlr::ReportsAsSparkline::CumulatedReport.new(User, :registrations,
                :aggregation => :count,
                :grouping    => grouping,
                :limit       => 10,
                :live_data   => live_data
              )
              result = @report.run

              result[10][1].should == 3.0 if live_data
              result[9][1].should  == 3.0
              result[8][1].should  == 2.0
              result[7][1].should  == 2.0
              result[6][1].should  == 0.0
            end

            it 'should return correct data for aggregation :sum' do
              @report = Kvlr::ReportsAsSparkline::CumulatedReport.new(User, :registrations,
                :aggregation  => :sum,
                :grouping     => grouping,
                :value_column => :profile_visits,
                :limit        => 10,
                :live_data    => live_data
              )
              result = @report.run()

              result[10][1].should == 6.0 if live_data
              result[9][1].should  == 6.0
              result[8][1].should  == 5.0
              result[7][1].should  == 5.0
              result[6][1].should  == 0.0
            end

            it 'should return correct data for aggregation :count when custom conditions are specified' do
              @report = Kvlr::ReportsAsSparkline::CumulatedReport.new(User, :registrations,
                :aggregation => :count,
                :grouping    => grouping,
                :limit       => 10,
                :live_data   => live_data
              )
              result = @report.run(:conditions => ['login IN (?)', ['test 1', 'test 2']])

              result[10][1].should == 2.0 if live_data
              result[9][1].should  == 2.0
              result[8][1].should  == 1.0
              result[7][1].should  == 1.0
              result[6][1].should  == 0.0
            end

            it 'should return correct data for aggregation :sum when custom conditions are specified' do
              @report = Kvlr::ReportsAsSparkline::CumulatedReport.new(User, :registrations,
                :aggregation  => :sum,
                :grouping     => grouping,
                :value_column => :profile_visits,
                :limit        => 10,
                :live_data    => live_data
              )
              result = @report.run(:conditions => ['login IN (?)', ['test 1', 'test 2']])

              result[10][1].should == 3.0 if live_data
              result[9][1].should  == 3.0
              result[8][1].should  == 2.0
              result[7][1].should  == 2.0
              result[6][1].should  == 0.0
            end

          end

          after(:all) do
            User.destroy_all
          end

        end

      end

    end

    after(:each) do
      Kvlr::ReportsAsSparkline::ReportCache.destroy_all
    end

  end

  describe '#cumulate' do

    it 'should correctly cumulate the given data' do
      first = (Time.now - 1.week).to_s
      second = Time.now.to_s
      data = [[first, 1], [second, 2]]

      @report.send(:cumulate, data, @report.send(:options_for_run, {})).should == [[first, 1.0], [second, 3.0]]
    end

  end

end
