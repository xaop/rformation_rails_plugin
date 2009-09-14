class FormController < ApplicationController

  def index
  end

  def form
  end

  def corporate_form
    @corporate = true
    render :action => "form"
  end

  def submit_form
    if params[:commit] == "Cancel"
      render :action => "cancel"
    else
      @user = params[:user]
      @company = params[:company]
      @corporate = params[:corporate]
      if params[:form_errors].blank?
      
      else
        # The 3 assignments above are used to repopulate the form automatically
        @errors = params[:form_errors]
        render :action => "form"
      end
    end
  end

end
