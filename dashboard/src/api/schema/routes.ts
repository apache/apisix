import request from '@/utils/request'
import { IRouteData } from '../types'

export const getList = () =>
  request({
    url: '/routes',
    method: 'GET'
  })

export const update = (id: string, params: IRouteData) =>
  request({
    url: `/routes/${id}`,
    method: 'PUT',
    params
  })

export const getRouter = (id: string) =>
  request({
    url: `/routes/${id}`,
    method: 'GET'
  })

export const removeRouter = (id: string) =>
  request({
    url: `/routes/${id}`,
    method: 'DELETE'
  })

export const create = (params: IRouteData) =>
  request({
    url: '/routes',
    method: 'POST',
    params
  })
