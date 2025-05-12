import axios, { Method, RawAxiosRequestHeaders } from 'axios';

export const request = async (
  uri: string,
  method: Method = 'GET',
  body?: object,
  headers?: RawAxiosRequestHeaders,
) => {
  return axios.request({
    method,
    // TODO: use 9180 for admin api
    url: `http://127.0.0.1:1984/${uri}`,
    data: body,
    headers: {
      'X-API-KEY': 'edd1c9f034335f136f87ad84b625c8f1',
      ...headers,
    },
  });
};
