import request from '@/utils/request'

enum Type {
    chash,
    roundrobin
}

enum Key {
    remote_addr
}

type UpstreamType = {
    nodes: object
    type: Type
    key?: Key
    id?: number | string
}

export const update = (id: string, params: UpstreamType) =>
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

export const create = (params: UpstreamType) =>
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