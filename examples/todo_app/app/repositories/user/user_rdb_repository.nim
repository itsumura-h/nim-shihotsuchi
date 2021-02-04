import json
import allographer/query_builder
import ../../core/models/user/user_repository_interface
import ../../core/models/user/user_entity
import ../../core/value_objects


type UserRdbRepository* = ref object

proc newUserRdbRepository*():UserRdbRepository =
  return UserRdbRepository()


proc storeUser*(
  this:UserRdbRepository,
  name:UserName,
  email:UserEmail,
  hashedPassword:HashedPassword
):UserId =
  let userIdData = rdb()
                  .table("users")
                  .insertID(%*{
                    "name": $name,
                    "email": $email,
                    "password": $hashedPassword
                  })
  let userId = newUserId(userIdData)
  return userId

proc getUser*(this:UserRdbRepository, email:UserEmail):User =
  let userData = rdb().table("users").where("email", "=", $email).first()
  let id = newUserId(userData["id"].getInt)
  let name = newUserName(userData["name"].getStr)
  let hashedPassword = newHashedPassword(userData["password"].getStr)
  let user = newUser(id, name, email, hashedPassword)
  return user


proc toInterface*(this:UserRdbRepository):IUserRepository =
  return (
    storeUser: proc(
        name:UserName, email:UserEmail, hashedPassword:HashedPassword
      ):UserId = this.storeUser(name, email, hashedPassword),
    getUser: proc(email:UserEmail):User = this.getUser(email)
  )
