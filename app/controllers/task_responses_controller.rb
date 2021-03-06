# Copyright 2012 Twitter, Inc. and others.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'csv'

class TaskResponsesController < ApplicationController
  before_filter :find_response, :except => [:index, :responses_csv]
  before_filter :require_priv, :except => [:index, :responses_csv]

  # caches_action :index, :layout => false, :if => proc{request.format.html?}

  private

  def find_response
    @response = TaskResponse.find(params[:id])
  end

  def require_priv
    if @response.task.evaluation.prod? and !current_user.privileged?
      render :json => {:status => "Forbidden"}, :status => 403
    end
  end

  public

  # GET /evaluations/1/task_responses
  # GET /evaluations/1/task_responses.json
  def index
    @eval = Evaluation.includes({
      :task_responses => {:mc_question_responses => [:mc_question_option], :fr_question_responses => [], :task => [], :m_turk_user => []},
      :fr_questions => [:fr_question_responses],
      :mc_questions => {:mc_question_options => [:mc_question_responses => [:mc_question_option]]}
    }).find(params[:evaluation_id])

    #@indixResp = FRQuestion.includes([:fr_question_responses]).where(:evaluation_id=>@eval.id)



    @task_responses = @eval.task_responses

    # assemble JSON data to send to client for visualization. We send a data
    # Hash with for elements:
    #
    # @data[:mcQuestions]
    #   a hash of <id> => {:label => <label>. :options => [<option ids>]}
    #   with an element for each MCQuestion
    # @data[:mcQuestionOptions]
    #   a hash of
    #   <id> => {
    #     :label => <label>,
    #     :value => <value>
    #     :question => <mc question id>
    #   }
    #   with an element for each MCQuestionOption
    # @data[:frQuestions]
    #   a hash of <id> => {:label => <label>} with an element for each
    #   FRQuestion
    # @data[:responses]
    #   a hash of
    #   <id> => {
    #     :frQuestions => {
    #        <fr question 1 id> => <response text>,
    #        <fr question 2 id> => <response text>,
    #        ... entry for each FRQuestion ...
    #     },
    #     :mcQuestions => {
    #        <mc question 1 id> => <mc question option id>,
    #        <mc question 2 id> => <mc question option id>,
    #        ... entry for each MCQuestion ...
    #     }
    #     :approved => <false if rejected, true if approved or no decision yet>
    #   }
    #   with an element for each TaskResponse
    #
    # An sample @data is in TaskResponsesControllerTest#test_index
    mc_questions = {}
    mc_question_options = {}
    @eval.mc_questions.each do |mc_q|
      mc_questions[mc_q.id] = {
        :label => mc_q.label,
        :options => mc_q.mc_question_options.map{|opt| opt.id}
      }

      mc_q.mc_question_options.each do |opt|
        mc_question_options[opt.id] = {
          :label => opt.label,
          :value => opt.value,
          :question => opt.mc_question_id
        }
      end
    end

    fr_questions = {}
    @eval.fr_questions.each do |fr_q|
      fr_questions[fr_q.id] = {
        :label => fr_q.label
      }
    end

    responses = {}
    @task_responses.each do |resp|
      fr_question_responses = {}

      resp.fr_question_responses.each do |fr_resp|
        fr_question_responses[fr_resp.fr_question_id] = fr_resp.response
      end

      mc_question_responses = {}

      resp.mc_question_responses.each do |mc_resp|
        mc_question_responses[mc_resp.mc_question_option.mc_question_id] = mc_resp.mc_question_option_id
      end

      responses[resp.id] = {
        :frQuestions => fr_question_responses,
        :mcQuestions => mc_question_responses,
        :approved => (resp.approved.nil? or resp.approved?)
      }
    end

    frqs = FRQuestion.includes(:fr_question_responses=>[:task_response=>[:task]]).where(:evaluation_id => @eval.id)

    report = {}
    pr={}

    frqs.each do |frq|
      report[frq.id] = {}
      frq.fr_question_responses.each do |frqres| # 30 items
        frqres.task_response.task.data.each do |entry| # 5 items
          if entry['id'] == frqres.response.split('_').first
            entry['cwr_resp'] = frqres.response.split('_').second

            if pr[entry['cwr_resp']].blank?
              pr[entry['cwr_resp']] = {:tp=>0,:fp=>0,:fn=>0}
            end

            if entry['ClassifierResult'] == entry['cwr_resp']
              pr[entry['cwr_resp']][:tp] += 1
            elsif entry['ClassifierResult'] != entry['cwr_resp'] and entry['ClassifierResult'] != "null"
              pr[entry['cwr_resp']][:fp] += 1
            else
              pr[entry['cwr_resp']][:fn] += 1
            end                
          end
        end
        report[frq.id][frqres.task_response.task.id] = {:data => frqres.task_response.task.data}
      end
    end
    
    @data = {
      :mcQuestions => mc_questions,
      :mcQuestionOptions => mc_question_options,
      :frQuestions => fr_questions,
      :responses => responses,
      :indixResponse => report,
      :precisionRecall => pr
    }



    respond_to do |format|
      format.html # index.html.erb
      format.json { render :json => @data }
      format.csv {
        render :text => responses_csv(','),  :type => 'text/csv',
                                             :filename => 'responses.csv',
                                             :disposition => 'attachment',
                                             :layout => false
      }
      format.tsv {
        render :text => responses_csv("\t"), :type => 'text/tab-separated-values',
                                             :filename => 'responses.tsv',
                                             :disposition => 'attachment',
                                             :layout => false
      }
    end
  end

  def approve
    @response.approve!
    expire_action(:action => 'index', :evaluation_id => @response.task.evaluation)
    render :json => {:status => "Approved"}
  end

  def reject
    @response.reject!
    expire_action(:action => 'index', :evaluation_id => @response.task.evaluation)
    render :json => {:status => "Rejected"}
  end

  def responses_csv(sep = ',')
    CSV.generate(:col_sep => sep) do |csv|
      # Pull out the fields that were uploaded with the original data,
      # so that we can output these along with the task responses.
      orig_fields_keys = if @task_responses.empty? 
                           []
                         else 
                           @task_responses.first.task.data.first.keys
                         end

      # As a slightly hacky way of dealing with metadata, Clockwork Raven stores
      # these metadata as MC questions in the eval. This pulls out the
      # _true_ MC questions (i.e., questions that aren't metadata), so that we
      # don't doubly output any fields that were uploaded with the original data.
      real_mc_questions = @eval.mc_questions.select{|mc_q| !mc_q.metadata }
                               
      # headers
      csv << orig_fields_keys + 
             (real_mc_questions + @eval.fr_questions).map{|q| q.label} +
             ["MTurk User", "Work Duration", "Approval"]

      @task_responses.each do |task_response|
        task_response.task.data.each do |d|
          # build the row
          row = []

          # Fields from the original data file.
          orig_fields_keys.each do |k|
            row.push(d[k])
          end


          # MC Questions
          # real_mc_questions.each do |mc_q|
          #   option_id = @data[:responses][task_response.id][:mcQuestions][mc_q.id]
          #   mc_q_resp = option_id.nil? ? nil : @data[:mcQuestionOptions][option_id][:label]
          #   row.push(mc_q_resp.nil? ? nil : mc_q_resp)
          # end

          # FR Questions
          @eval.fr_questions.each do |fr_q|
            unless @data[:indixResponse][fr_q.id].blank?
              @data[:indixResponse][fr_q.id][task_response.task.id][:data].each do |q|
                if d['id'] == q['id']
                  fr_q_resp = q['cwr_resp']  
                  row.push(fr_q_resp.nil? ? nil : fr_q_resp)
                end
              end
            end
            # fr_q_resp = @data[:responses][task_response.id][:frQuestions][fr_q.id]
            
          end

          row.push(task_response.m_turk_user_id)
          row.push(task_response.work_duration)
          row.push(task_response.approved)

          csv << row
        end
      end
    end
  end
end
