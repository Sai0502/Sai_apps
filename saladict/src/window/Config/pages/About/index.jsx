import { Button, Divider } from '@nextui-org/react';
import { appLogDir, appConfigDir } from '@tauri-apps/api/path';
import { useTranslation } from 'react-i18next';
import { open } from '@tauri-apps/api/shell';
import React from 'react';
import { useConfig } from '../../../../hooks/useConfig';
import { appVersion } from '../../../../utils/env';

export default function About() {
    const { t } = useTranslation();
    const [devMode] = useConfig('dev_mode', false);

    return (
        <div className='h-full w-full py-[80px] px-[100px]'>
            <img
                src='icon.png'
                className='mx-auto h-[100px] mb-[5px]'
                draggable={false}
            />
            <div className='content-center'>
                <h1 className='font-bold text-2xl text-center'>{t('config.about.app_name')}</h1>
                <p className='text-center text-sm text-gray-500 mb-[5px]'>{appVersion}</p>
                <Divider />
            </div>
            <div className='content-center px-[40px]'>
                <div className='flex justify-center'>
                    {devMode && (
                        <Button
                            variant='light'
                            className='my-[5px]'
                            size='sm'
                            onPress={async () => {
                                const dir = await appLogDir();
                                open(dir);
                            }}
                        >
                            {t('config.about.view_log')}
                        </Button>
                    )}
                    {devMode && (
                        <Button
                            variant='light'
                            className='my-[5px]'
                            size='sm'
                            onPress={async () => {
                                const dir = await appConfigDir();
                                open(dir);
                            }}
                        >
                            {t('config.about.view_config')}
                        </Button>
                    )}
                </div>
                <Divider />
            </div>
        </div>
    );
}
