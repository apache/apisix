import request from '@/utils/request'

type SSLType = {
  cert: string
  key: string
  sni: string
}

export const getList = (params: any) =>
  request({
    url: '/ssl',
    method: 'GET',
    params
  })

export const set = (id: string, params: SSLType) =>
  request({
    url: `/ssl/${id}`,
    method: 'PUT',
    params
  })

export const get = (id: string) =>
request({
  url: `/ssl/${id}`,
  method: 'GET'
})

export const remove = (id: string) =>
  request({
    url: `/ssl/${id}`,
    method: 'DELETE'
  })

export const create = (params: SSLType) =>
request({
  url: '/ssl',
  method: 'POST',
  params
})