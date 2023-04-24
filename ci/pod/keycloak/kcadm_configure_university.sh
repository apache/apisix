#!/usr/bin/env bash

#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

export PATH=/opt/keycloak/bin:$PATH

kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password admin

# create realm University
kcadm.sh create realms -s realm=University -s enabled=true

# create roles `Teacher, Student`
kcadm.sh create roles -r University -s name=Teacher
kcadm.sh create roles -r University -s name=Student

# create users `teacher@gmail.com, student@gmail.com`
kcadm.sh create users -r University -s username=teacher@gmail.com -s enabled=true
kcadm.sh create users -r University -s username=student@gmail.com -s enabled=true

# set password
kcadm.sh set-password -r University --username teacher@gmail.com --new-password 123456
kcadm.sh set-password -r University --username student@gmail.com --new-password 123456

# bind roles to users
kcadm.sh add-roles -r University --uusername teacher@gmail.com --rolename Teacher
kcadm.sh add-roles -r University --uusername student@gmail.com --rolename Student

# create client course_management
kcadm.sh create clients -r University -s clientId=course_management -s enabled=true -s clientAuthenticatorType=client-secret -s secret=d1ec69e9-55d2-4109-a3ea-befa071579d5

client_id=$(kcadm.sh get clients -r University --fields id,clientId 2>/dev/null | jq -r '.[] | select(.clientId=='\"course_management\"') | .id')
teacher_id=$(kcadm.sh get roles -r University --fields id,name 2>/dev/null | jq -r '.[] | select(.name=='\"Teacher\"') | .id')
student_id=$(kcadm.sh get roles -r University --fields id,name 2>/dev/null | jq -r '.[] | select(.name=='\"Student\"') | .id')

# update client course_management
kcadm.sh update clients/${client_id} -r University -s protocol=openid-connect -s standardFlowEnabled=true \
  -s implicitFlowEnabled=true -s directAccessGrantsEnabled=true -s serviceAccountsEnabled=true \
  -s authorizationServicesEnabled=true -s 'redirectUris=["*"]' -s 'webOrigins=["*"]'

kcadm.sh update clients/${client_id}/authz/resource-server -r University -s allowRemoteResourceManagement=false -s policyEnforcementMode="ENFORCING"

# create authz-resource with name `course_resource`, uri `/course/*`, scope `DELETE, delete, view, GET`
kcadm.sh create clients/${client_id}/authz/resource-server/resource -r University -s name=course_resource \
  -s ownerManagedAccess=false -s uris='["/course/*"]' -s scopes='[{"name": "DELETE"},{"name": "view"},{"name": "GET"},{"name": "delete"}]'

course_resource_id=$(kcadm.sh get clients/${client_id}/authz/resource-server/resource -r University --fields _id,name 2>/dev/null | jq -r '.[] | select(.name=='\"course_resource\"') | ._id')
DELETE_scope_id=$(kcadm.sh get clients/${client_id}/authz/resource-server/scope -r University --fields id,name 2>/dev/null | jq -r '.[] | select(.name=='\"DELETE\"') | .id')
delete_scope_id=$(kcadm.sh get clients/${client_id}/authz/resource-server/scope -r University --fields id,name 2>/dev/null | jq -r '.[] | select(.name=='\"delete\"') | .id')
GET_scope_id=$(kcadm.sh get clients/${client_id}/authz/resource-server/scope -r University --fields id,name 2>/dev/null | jq -r '.[] | select(.name=='\"GET\"') | .id')
view_scope_id=$(kcadm.sh get clients/${client_id}/authz/resource-server/scope -r University --fields id,name 2>/dev/null | jq -r '.[] | select(.name=='\"view\"') | .id')

# create authz-policy `AllowTeacherPolicy, AllowStudentPolicy`
kcadm.sh create clients/${client_id}/authz/resource-server/policy/role -r University \
  -s name="AllowTeacherPolicy" -s logic="POSITIVE" -s decisionStrategy="UNANIMOUS" \
  -s roles='[{"id": '\"${teacher_id}\"'}]'

kcadm.sh create clients/${client_id}/authz/resource-server/policy/role -r University \
  -s name="AllowStudentPolicy" -s logic="POSITIVE" -s decisionStrategy="UNANIMOUS" \
  -s roles='[{"id": '\"${student_id}\"'}]'

allow_teacher_policy_id=$(kcadm.sh get clients/${client_id}/authz/resource-server/policy -r University --fields id,name 2>/dev/null | jq -r '.[] | select(.name=='\"AllowTeacherPolicy\"') | .id')
allow_student_policy_id=$(kcadm.sh get clients/${client_id}/authz/resource-server/policy -r University --fields id,name 2>/dev/null | jq -r '.[] | select(.name=='\"AllowStudentPolicy\"') | .id')

# create authz-permission `Delete Course Permission` and `View Course Permission`
kcadm.sh create clients/${client_id}/authz/resource-server/permission/scope -r University \
  -s name="Delete Course Permission" -s logic="POSITIVE" -s decisionStrategy="UNANIMOUS" \
  -s policies='['\"${allow_teacher_policy_id}\"']' \
  -s scopes='['\"${DELETE_scope_id}\"', '\"${delete_scope_id}\"']' \
  -s resources='['\"${course_resource_id}\"']'

kcadm.sh create clients/${client_id}/authz/resource-server/permission/scope -r University \
  -s name="View Course Permission" -s logic="POSITIVE" -s decisionStrategy="AFFIRMATIVE" \
  -s policies='['\"${allow_teacher_policy_id}\"', '\"${allow_student_policy_id}\"']' \
  -s scopes='['\"${GET_scope_id}\"', '\"${view_scope_id}\"']' \
  -s resources='['\"${course_resource_id}\"']'
