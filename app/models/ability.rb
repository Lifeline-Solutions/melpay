class Ability
  include CanCan::Ability

  def initialize(user)
    user ||= User.new # guest user (not logged in)

    if user.has_role? :super_admin
      can :manage, :all
    elsif user.has_role? :admin
      # Admin can only manage resources within their own client
      can :manage, User, client_id: user.client_id
      can :manage, Home, client_id: user.client_id
      can :manage, Account, client_id: user.client_id
    elsif user.has_role? :account_manager
      can :read, User, client_id: user.client_id, user_id: user.id
      can :manage, Home, client_id: user.client_id, user_id: user.id
    elsif user.has_role? :auditor
      can :read, User, client_id: user.client_id
      can :read, Home, client_id: user.client_id
      can :read, Account, client_id: user.client_id
    else
      cannot :manage, :all
    end
  end
end
