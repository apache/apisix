import request from '@/utils/request'

import { IUpstreamData } from '../types'

export const update = (id: string, params: IUpstreamData) =>
  request({
    url: `/upstreams/${id}`,
    method: 'PUT',
    params
  })

export const get = (id: string) =>
  request({
    url: `/upstreams/${id}`,
    method: 'GET'
  })

export const remove = (id: string) =>
  request({
    url: `/upstreams/${id}`,
    method: 'DELETE'
  })

export const create = (params: IUpstreamData) =>
  request({
    url: `/upstreams`,
    method: 'POST',
    params
  })

export const getList = () =>
  request({
    url: `/upstreams`,
    method: 'GET'
  })
