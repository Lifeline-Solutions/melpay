class Ability
  include CanCan::Ability

  def initialize(user)
    user ||= User.new # guest user (not logged in)

    if user.has_role? :super_admin
      can :manage, :all
      can :invite, User

    elsif user.has_role? :admin
      # Admin can manage all users and homes within their client
      can :manage, User, client_id: user.client_id
      can :manage, Home, client_id: user.client_id
      can :read, Transaction, client_id: user.client_id
      can :create, Transaction, client_id: user.client_id
      can :invite, User
      can :read, Client, id: user.client_id

    elsif user.has_role? :account_manager
      # Account Manager can only see users in their client, but only manage their own homes/transactions
      can :read, User, client_id: user.client_id
      # READ all homes in client
      can :read, Home, client_id: user.client_id
      # MANAGE only their own data for their own client
      can :manage, Home, user_id: user.id, client_id: user.client_id
      can :read, Transaction, client_id: user.client_id
      can :create, Transaction, user_id: user.id, client_id: user.client_id
      can :read, Client, id: user.client_id

    elsif user.has_role? :auditor
      # Auditor can see all but cannot manage anything
      can :read, :all
      cannot :manage, :all

    else
      # Regular User (no specific role)
      cannot :manage, :all
    end
  end
end
